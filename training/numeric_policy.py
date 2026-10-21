"""Frozen policy HTTP requests over Planet Wars' ordinary private features."""

from __future__ import annotations

from urllib.request import Request, urlopen
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field, FiniteFloat

from .sprite_view import ACTION_MASKS, OBSERVATION_SIZE


class ChoiceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    session: str = Field(min_length=1)
    seat: int = Field(ge=0, lt=8)
    decision_id: int = Field(ge=0)
    values: list[FiniteFloat] = Field(min_length=OBSERVATION_SIZE, max_length=OBSERVATION_SIZE)
    action_mask: list[bool] = Field(min_length=len(ACTION_MASKS), max_length=len(ACTION_MASKS))


class ChoiceResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    choice: int = Field(ge=0, lt=len(ACTION_MASKS))


class NumericPolicy:
    def __init__(self, endpoint: str) -> None:
        self.endpoint = endpoint
        self.session = uuid4().hex

    def action(self, observation: tuple[float, ...], seat: int, decision_id: int) -> int:
        request = ChoiceRequest(
            session=self.session,
            seat=seat,
            decision_id=decision_id,
            values=list(observation),
            action_mask=[True] * len(ACTION_MASKS),
        )
        body = Request(
            self.endpoint,
            data=request.model_dump_json().encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(body, timeout=5) as response:
            return ChoiceResponse.model_validate_json(response.read()).choice
