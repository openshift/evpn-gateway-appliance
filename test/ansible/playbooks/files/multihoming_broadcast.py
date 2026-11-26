#!/usr/bin/env python3
"""Send one identifiable Ethernet broadcast or count copies on a VLAN."""

import argparse
import socket
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("send", "receive"))
    parser.add_argument("interface")
    parser.add_argument("token")
    parser.add_argument("ready_file", nargs="?", type=Path)
    args = parser.parse_args()
    broadcast = b"\xff" * 6
    ethertype = bytes.fromhex("88b5")
    payload = args.token.encode("ascii")

    with socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)) as packet:
        packet.bind((args.interface, 0))
        if args.mode == "send":
            source = packet.getsockname()[4]
            packet.send((broadcast + source + ethertype + payload).ljust(60, b"\0"))
            return

        args.ready_file.touch()
        deadline = time.monotonic() + 5
        count = 0
        while (remaining := deadline - time.monotonic()) > 0:
            packet.settimeout(remaining)
            try:
                frame, address = packet.recvfrom(2048)
            except TimeoutError:
                break
            if (
                address[2] != socket.PACKET_OUTGOING
                and frame.startswith(broadcast)
                and frame[12:].startswith(ethertype + payload)
            ):
                count += 1
        if count != 1:
            raise SystemExit(f"Expected one broadcast on {args.interface}, received {count}")


if __name__ == "__main__":
    main()
