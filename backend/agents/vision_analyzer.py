# agents/vision_analyzer.py
# 调用 Gemini 多模态接口分析相机帧，识别拍摄问题

import base64
import json
import re
from openai import AsyncOpenAI
from models.request_models import VisionResult, IssueDetail, SensorData
import config

_client = AsyncOpenAI(
    api_key=config.LLM_API_KEY,
    base_url=config.LLM_BASE_URL,
)

VISION_PROMPT = """
你是一个专业的手机摄影助手，正在帮用户实时改善拍照质量。

请分析这张相机取景帧，识别存在的拍摄问题。
结合以下传感器数据辅助判断：
{sensor_context}

请只输出 JSON，不要任何解释或 markdown 代码块，格式如下：

{{
  "lighting": {{
    "issue": true或false,
    "detail": "过暗/过曝/逆光/色温偏冷/色温偏暖/正常",
    "severity": 1到3的整数
  }},
  "composition": {{
    "issue": true或false,
    "detail": "主体偏左/主体偏右/主体居中建议三分法/主体偏上/主体偏下/无明显主体/构图良好",
    "severity": 1到3的整数
  }},
  "stability": {{
    "issue": true或false,
    "detail": "画面模糊/轻微抖动/稳定",
    "severity": 1到3的整数
  }},
  "focus": {{
    "issue": true或false,
    "detail": "对焦失准/对焦中/对焦准确",
    "severity": 1到3的整数
  }},
  "other": {{
    "issue": true或false,
    "detail": "镜头有污渍/玻璃反光/遮挡物/无异常",
    "severity": 1到3的整数
  }}
}}

severity 含义：1=轻微问题，2=中等问题，3=严重问题。
没有问题时 issue 为 false，severity 填 1。
"""


async def analyze(frame_base64: str, sensor_data: SensorData) -> VisionResult:
    """
    调用 DeepSeek 分析帧图像，返回结构化视觉分析结果。
    若 API 调用失败，返回空结果（不中断主流程）。
    """
    sensor_context = (
        f"设备倾斜：X轴 {sensor_data.tilt_x:.1f}°，Y轴 {sensor_data.tilt_y:.1f}°\n"
        f"本地亮度估值：{sensor_data.brightness:.2f}（0最暗，1最亮）\n"
        f"对焦状态：{'正在对焦中' if sensor_data.is_focusing else '对焦稳定'}"
    )

    prompt = VISION_PROMPT.format(sensor_context=sensor_context)

    try:
        print(f"[VisionAnalyzer] 开始调用 model={config.LLM_MODEL}, sensor={sensor_context}")
        response = await _client.chat.completions.create(
            model=config.LLM_MODEL,
            max_tokens=512,
            temperature=0.1,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{frame_base64}"
                            }
                        },
                        {
                            "type": "text",
                            "text": prompt
                        }
                    ]
                }
            ]
        )

        raw = response.choices[0].message.content or ""
        print(f"[VisionAnalyzer] 模型返回: {raw[:200]}")
        return _parse_result(raw)

    except Exception as e:
        print(f"[VisionAnalyzer] 模型调用失败: {e}")
        return VisionResult()


def _parse_result(raw: str) -> VisionResult:
    """安全解析 DeepSeek 返回的 JSON，容错格式不规范的情况"""
    try:
        # 去除可能残留的 markdown 代码块标记
        cleaned = re.sub(r"```(?:json)?|```", "", raw).strip()
        data = json.loads(cleaned)

        def to_detail(d: dict) -> IssueDetail:
            return IssueDetail(
                issue=bool(d.get("issue", False)),
                detail=str(d.get("detail", "")),
                severity=int(d.get("severity", 1))
            )

        return VisionResult(
            lighting=to_detail(data.get("lighting", {})),
            composition=to_detail(data.get("composition", {})),
            stability=to_detail(data.get("stability", {})),
            focus=to_detail(data.get("focus", {})),
            other=to_detail(data.get("other", {})),
        )

    except Exception as e:
        print(f"[VisionAnalyzer] JSON 解析失败: {e}\n原始内容: {raw[:200]}")
        return VisionResult()
