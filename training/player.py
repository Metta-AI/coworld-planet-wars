"""Run a trained numeric policy as an ordinary Planet Wars player."""

from __future__ import annotations

import os
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from websockets.sync.client import connect

from .numeric_policy import NumericPolicy
from .sprite_view import ACTION_MASKS, SpriteView


def main() -> None:
    endpoint = urlsplit(os.environ["COWORLD_PLAYER_WS_URL"])
    query = dict(parse_qsl(endpoint.query))
    name = query.setdefault("name", "trained-policy")
    url = urlunsplit(endpoint._replace(query=urlencode(query)))
    policy = NumericPolicy(os.environ["PLAYER_NUMERIC_URL"])
    view = SpriteView(name)
    frame = 0
    previous_mask = 0
    with connect(url, max_size=None, ping_timeout=None) as socket:
        for packet in socket:
            if isinstance(packet, str):
                continue
            view.apply(packet)
            if view.own_player_id is None:
                continue
            frame += 1
            if frame % 6 != 1:
                continue
            mask = ACTION_MASKS[policy.action(view.features(), view.own_player_id - 1, frame)]
            if mask != previous_mask:
                socket.send(bytes((0x84, mask)))
                previous_mask = mask


if __name__ == "__main__":
    main()
