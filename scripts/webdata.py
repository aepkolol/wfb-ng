#!/usr/bin/env python3

import sys
import msgpack
import tempfile
import argparse
import json

from twisted.python import log
from twisted.internet import reactor, defer
from twisted.internet.protocol import ReconnectingClientFactory
from twisted.protocols.basic import Int32StringReceiver

from autobahn.twisted.websocket import WebSocketServerFactory, WebSocketServerProtocol

from wfb_ng.server import parse_services
from wfb_ng.common import abort_on_crash, exit_status
from wfb_ng.conf import settings
from wfb_ng import version_msg

# Functions used in data processing
def human_rate(r):
    rate = r * 8

    if rate >= 1000 * 1000:
        rate = rate / 1024 / 1024
        mod = 'mbit/s'
    else:
        rate = rate / 1024
        mod = 'kbit/s'

    if rate < 10:
        return '%0.1f %s' % (rate, mod)
    else:
        return '%3d %s' % (rate, mod)

def format_ant(ant_id):
    if ant_id < (1 << 32):
        if ant_id & 0xff == 0xff:
            return '%2X:X ' % (ant_id >> 8)
        else:
            return '%2X:%X ' % (ant_id >> 8, ant_id & 0xff)

    if ant_id & 0xff == 0xff:
        return '%08X:%X:X' % (ant_id >> 32, (ant_id >> 8) & 0xff)
    else:
        return '%08X:%X:%X' % (ant_id >> 32, (ant_id >> 8) & 0xff, ant_id & 0xff)

class MyWebSocketServerProtocol(WebSocketServerProtocol):
    def onOpen(self):
        self.factory.register(self)

    def onClose(self, wasClean, code, reason):
        self.factory.unregister(self)

    def onMessage(self, payload, isBinary):
        pass  # Handle incoming messages from clients if needed

class MyWebSocketServerFactory(WebSocketServerFactory):
    protocol = MyWebSocketServerProtocol

    def __init__(self, url):
        super().__init__(url)
        self.clients = []

    def register(self, client):
        if client not in self.clients:
            self.clients.append(client)

    def unregister(self, client):
        if client in self.clients:
            self.clients.remove(client)

    def broadcast(self, msg):
        for c in self.clients:
            c.sendMessage(msg.encode('utf8'))

class AntennaStat(Int32StringReceiver):
    MAX_LENGTH = 1024 * 1024
    is_cluster = False
    log_interval = settings.common.log_interval
    temp_overheat_warning = settings.common.temp_overheat_warning

    def stringReceived(self, string):
        attrs = msgpack.unpackb(string, strict_map_key=False, use_list=False, raw=False)

        if attrs['type'] == 'rx':
            data = self.process_rx(attrs)
        elif attrs['type'] == 'tx':
            data = self.process_tx(attrs)
        elif attrs['type'] == 'cli_title':
            # Fallbacks added for compatibility with old server versions
            self.is_cluster = attrs.get('is_cluster', False)
            self.log_interval = attrs.get('log_interval', settings.common.log_interval)
            self.temp_overheat_warning = attrs.get('temp_overheat_warning', settings.common.temp_overheat_warning)
            data = {'type': 'cli_title', 'cli_title': attrs['cli_title']}
        else:
            data = attrs  # Unknown type, send as-is

        # Send data over WebSocket
        self.factory.websocket_factory.broadcast(json.dumps(data))

    def process_rx(self, attrs):
        p = attrs['packets']
        session_d = attrs['session']
        stats_d = attrs['rx_ant_stats']
        tx_wlan = attrs.get('tx_wlan')
        rx_id = attrs['id']

        data = {
            'type': 'rx',
            'id': rx_id,
            'packets': p,
            'session': session_d,
            'rx_ant_stats': stats_d,
            'tx_wlan': tx_wlan,
            'flow': {
                'recv_rate': human_rate(1000 * p['all_bytes'][0] / self.log_interval),
                'out_rate': human_rate(1000 * p['out_bytes'][0] / self.log_interval)
            }
        }
        return data

    def process_tx(self, attrs):
        p = attrs['packets']
        latency_d = attrs['latency']
        tx_id = attrs['id']
        rf_temperature = attrs['rf_temperature']

        data = {
            'type': 'tx',
            'id': tx_id,
            'packets': p,
            'latency': latency_d,
            'rf_temperature': rf_temperature,
            'flow': {
                'incoming_rate': human_rate(1000 * p['incoming_bytes'][0] / self.log_interval),
                'injected_rate': human_rate(1000 * p['injected_bytes'][0] / self.log_interval)
            }
        }
        return data

class AntennaStatClientFactory(ReconnectingClientFactory):
    noisy = False
    maxDelay = 1.0

    def __init__(self, profile, websocket_factory):
        self.profile = profile
        self.websocket_factory = websocket_factory

    def buildProtocol(self, addr):
        self.resetDelay()
        p = AntennaStat()
        p.factory = self
        return p

    def clientConnectionLost(self, connector, reason):
        ReconnectingClientFactory.clientConnectionLost(self, connector, reason)

    def clientConnectionFailed(self, connector, reason):
        ReconnectingClientFactory.clientConnectionFailed(self, connector, reason)

def main():
    stderr = sys.stderr

    parser = argparse.ArgumentParser(description='WFB-ng CLI',
                                     formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('--version', action='version', version=version_msg % settings)
    parser.add_argument('--host', type=str, default='127.0.0.1', help='WFB-ng host')
    parser.add_argument('profile', type=str, help='WFB-ng profile')
    args = parser.parse_args()

    fd = tempfile.TemporaryFile(mode='w+', encoding='utf-8')
    log.startLogging(fd)

    # Set up the WebSocket server
    websocket_factory = MyWebSocketServerFactory(u"ws://0.0.0.0:9000")
    reactor.listenTCP(9000, websocket_factory)

    # Start the AntennaStat client
    stats_port = getattr(settings, args.profile).stats_port
    f = AntennaStatClientFactory(args.profile, websocket_factory)
    reactor.connectTCP(args.host, stats_port, f)

    # Run the reactor
    reactor.run()

    rc = exit_status()

    if rc:
        log.msg('Exiting with code %d' % rc)

    fd.seek(0)
    for l in fd:
        stderr.write(l)

    sys.exit(rc)

if __name__ == '__main__':
    main()
