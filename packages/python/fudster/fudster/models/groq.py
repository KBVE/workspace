from pydantic import ConfigDict, BaseModel, Field
from typing import List, Optional
from datetime import datetime


class AiGroqPayload(BaseModel):
    message: str
    model: str
    system: str


class GroqChoice(BaseModel):
    text: str
    index: int
    logprobs: Optional[dict] = None
    finish_reason: Optional[str] = None


class GroqUsage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class GroqResponse(BaseModel):
    id: str
    object: str
    created: datetime
    model: str
    choices: List[GroqChoice]
    usage: GroqUsage
    system_fingerprint: str
    x_groq: Optional[dict] = Field(None, alias='x_groq')

    model_config = ConfigDict(populate_by_name=True)
