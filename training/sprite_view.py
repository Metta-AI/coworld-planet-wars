"""Numeric features decoded from the ordinary Planet Wars private sprite wire."""

from __future__ import annotations

import struct
from dataclasses import dataclass


PLANET_COUNT = 48
FEATURES_PER_PLANET = 8
OBSERVATION_SIZE = 2 + PLANET_COUNT * FEATURES_PER_PLANET
BUTTON_UP = 1
BUTTON_DOWN = 2
BUTTON_LEFT = 4
BUTTON_RIGHT = 8
BUTTON_A = 32
BUTTON_B = 64
DIRECTIONS = (
    0,
    BUTTON_UP,
    BUTTON_DOWN,
    BUTTON_LEFT,
    BUTTON_RIGHT,
    BUTTON_UP | BUTTON_LEFT,
    BUTTON_UP | BUTTON_RIGHT,
    BUTTON_DOWN | BUTTON_LEFT,
    BUTTON_DOWN | BUTTON_RIGHT,
)
ACTION_MASKS = tuple(
    direction | buttons
    for direction in DIRECTIONS
    for buttons in (0, BUTTON_A, BUTTON_B, BUTTON_A | BUTTON_B)
)


@dataclass(frozen=True)
class Sprite:
    width: int
    height: int
    label: str


@dataclass(frozen=True)
class Object:
    x: int
    y: int
    sprite_id: int


class SpriteView:
    def __init__(self, player_name: str) -> None:
        self.player_name = player_name
        self.own_player_id: int | None = None
        self.sprites: dict[int, Sprite] = {}
        self.objects: dict[int, Object] = {}

    def apply(self, packet: bytes) -> None:
        offset = 0
        while offset < len(packet):
            kind = packet[offset]
            offset += 1
            if kind == 1:
                sprite_id, width, height, compressed_len = struct.unpack_from(
                    "<HHHI", packet, offset
                )
                offset += 10 + compressed_len
                label_len = struct.unpack_from("<H", packet, offset)[0]
                offset += 2
                label = packet[offset : offset + label_len].decode("utf-8")
                offset += label_len
                self.sprites[sprite_id] = Sprite(width, height, label)
            elif kind == 2:
                object_id, x, y, _, _, sprite_id = struct.unpack_from(
                    "<HhhhBH", packet, offset
                )
                offset += 11
                self.objects[object_id] = Object(x, y, sprite_id)
            elif kind == 3:
                object_id = struct.unpack_from("<H", packet, offset)[0]
                offset += 2
                del self.objects[object_id]
            elif kind == 4:
                self.objects.clear()
                self.own_player_id = None
            elif kind == 5:
                offset += 5
            elif kind == 6:
                offset += 3
            else:
                raise ValueError(f"unknown sprite message {kind}")
        if offset != len(packet):
            raise ValueError("sprite packet ended mid-message")
        for object_id, item in self.objects.items():
            if (
                13000 < object_id < 13000 + PLANET_COUNT
                and self.sprites[item.sprite_id].label
                == f"player name {self.player_name}"
            ):
                self.own_player_id = object_id - 13000

    def features(self) -> tuple[float, ...]:
        if self.own_player_id is None:
            raise ValueError(f"missing own cursor for {self.player_name}")
        own_player_id = self.own_player_id
        cursor = self.objects[12000 + own_player_id]
        cursor_x = cursor.x + 2
        cursor_y = cursor.y + 2
        values = [cursor_x / 320, cursor_y / 200]
        for planet_id in range(1, PLANET_COUNT + 1):
            object = self.objects.get(2000 + planet_id)
            if object is None:
                values.extend((0.0,) * FEATURES_PER_PLANET)
                continue
            sprite_id = object.sprite_id
            if 100 <= sprite_id < 108:
                owner, size = 0.0, sprite_id - 100
            elif 1000 <= sprite_id < 2000:
                owner_id = (sprite_id - 1000) // 8
                owner = 1.0 if owner_id == own_player_id else -owner_id / 8
                size = (sprite_id - 1000) % 8
            else:
                raise ValueError(f"unexpected planet sprite {sprite_id}")
            sprite = self.sprites[sprite_id]
            digits = [
                (index, item.sprite_id - 10000)
                for index in range(8)
                if (item := self.objects.get(2300 + planet_id * 8 + index)) is not None
            ]
            if any(not 0 <= digit <= 9 for _, digit in digits):
                raise ValueError(
                    f"unexpected ship count sprites for planet {planet_id}"
                )
            ships = int("".join(str(digit) for _, digit in digits)) if digits else 0
            values.extend(
                (
                    1.0,
                    owner,
                    ships / 1000,
                    (object.x + sprite.width / 2 - cursor_x) / 320,
                    (object.y + sprite.height / 2 - cursor_y) / 200,
                    size / 2,
                    float(2100 + planet_id in self.objects),
                    float(2200 + planet_id in self.objects),
                )
            )
        return tuple(values)
