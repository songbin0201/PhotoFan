# models/request_models.py
# 前后端通信的 Pydantic 数据结构

from pydantic import BaseModel, Field
from typing import Optional
import uuid


# ── 上行：iOS → 后端 ──

class SensorData(BaseModel):
    tilt_x: float = Field(0.0, description="设备 X 轴倾斜角（度）")
    tilt_y: float = Field(0.0, description="设备 Y 轴倾斜角（度）")
    brightness: float = Field(0.5, ge=0.0, le=1.0, description="本地亮度估值（0~1）")
    is_focusing: bool = Field(False, description="是否正在对焦")


class AnalyzeRequest(BaseModel):
    session_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    frame: str = Field(..., description="Base64 编码的 JPEG 图像")
    sensor_data: SensorData = Field(default_factory=SensorData)
    active_suggestions: list[str] = Field(
        default_factory=list,
        description="当前屏幕上已有的建议 type，避免重复推送"
    )


# ── 下行：后端 → iOS（SSE payload）──

class SuggestionPayload(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: str   # lighting / composition / stability / focus / tilt / other
    text: str   # 中文建议文字
    resolved: bool = False
    action: Optional[SuggestionAction] = None


class ResolvePayload(BaseModel):
    id: str
    resolved: bool = True


class ErrorPayload(BaseModel):
    message: str


# ── 视觉分析结果（内部流转）──

class IssueDetail(BaseModel):
    issue: bool = False
    detail: str = ""
    severity: int = Field(1, ge=1, le=3)   # 1=轻微 2=中等 3=严重


class VisionResult(BaseModel):
    lighting:    IssueDetail = Field(default_factory=IssueDetail)
    composition: IssueDetail = Field(default_factory=IssueDetail)
    stability:   IssueDetail = Field(default_factory=IssueDetail)
    focus:       IssueDetail = Field(default_factory=IssueDetail)
    other:       IssueDetail = Field(default_factory=IssueDetail)


# ── 操作动作 ──

class SuggestionAction(BaseModel):
    control: str = ""       # exposure / white_balance / iso / focus
    direction: str = ""     # increase / decrease / auto


# ── 内部建议对象 ──

class Suggestion(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: str
    text: str
    priority: int = Field(1, ge=1, le=3)
    action: Optional[SuggestionAction] = None
