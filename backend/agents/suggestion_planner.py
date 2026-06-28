# agents/suggestion_planner.py
# 将视觉分析结果 + 传感器数据 → 自然语言建议列表

from models.request_models import VisionResult, SensorData, Suggestion

# ── 建议文案模板 ──
# key 格式："{type}_{detail_keyword}"，精确匹配优先，否则用默认 key
_TEMPLATES: dict[str, str] = {

    # 光线
    "lighting_过暗":    "画面偏暗，点击屏幕提亮或调高曝光",
    "lighting_过曝":    "画面过曝，降低曝光补偿试试",
    "lighting_逆光":    "逆光拍摄，换个角度或开启 HDR",
    "lighting_色温偏冷": "色温偏冷，可手动调整白平衡",
    "lighting_色温偏暖": "色温偏暖，切换到自动白平衡",
    "lighting_default": "光线条件欠佳，尝试调整曝光",

    # 构图
    "composition_主体偏左":         "主体偏左，向右移动一些构图更佳",
    "composition_主体偏右":         "主体偏右，向左移动一些构图更佳",
    "composition_主体居中建议三分法": "主体居中，偏移至三分法交叉点更有层次",
    "composition_主体偏上":         "主体偏上，适当下移以平衡画面",
    "composition_主体偏下":         "主体偏下，适当上移留出空间",
    "composition_无明显主体":       "画面缺乏主体，靠近被摄物或重新取景",
    "composition_default":          "构图可以优化，参考三分法调整",

    # 稳定性
    "stability_画面模糊": "画面模糊，请稳住手机再拍",
    "stability_轻微抖动": "轻微抖动，深呼吸后按下快门",
    "stability_default":  "手机不够稳定，尝试靠墙或找支撑",

    # 对焦
    "focus_对焦失准": "对焦跑偏，轻触主体重新对焦",
    "focus_对焦中":   "正在对焦，请稍等片刻...",
    "focus_default":  "对焦异常，点击屏幕主体区域",

    # 其他
    "other_镜头有污渍": "镜头有污渍，擦拭后画质更清晰",
    "other_玻璃反光":   "有玻璃反光，调整拍摄角度避开",
    "other_遮挡物":     "有遮挡物进入画面，注意构图",
    "other_default":    "画面有异常，请检查拍摄环境",

    # 传感器直接判断
    "tilt_default": "手机倾斜了，请保持水平",
}

# 倾斜角阈值（度）
_TILT_THRESHOLD = 5.0


def plan(
    vision_result: VisionResult,
    sensor_data: SensorData,
    active_types: list[str],
    max_count: int = 3,
) -> list[Suggestion]:
    """
    根据视觉分析结果和传感器数据生成建议列表。
    - 过滤掉已在屏幕上的建议类型
    - 按 severity 降序排列，最多返回 max_count 条
    """
    candidates: list[Suggestion] = []

    # ── 1. 传感器直接判断（倾斜）──
    tilt_magnitude = (sensor_data.tilt_x ** 2 + sensor_data.tilt_y ** 2) ** 0.5
    if tilt_magnitude > _TILT_THRESHOLD and "tilt" not in active_types:
        candidates.append(Suggestion(
            type="tilt",
            text=f"手机倾斜 {tilt_magnitude:.0f}°，请保持水平",
            priority=2
        ))

    # ── 2. 视觉分析结果 ──
    checks = [
        ("lighting",    vision_result.lighting),
        ("composition", vision_result.composition),
        ("stability",   vision_result.stability),
        ("focus",       vision_result.focus),
        ("other",       vision_result.other),
    ]

    for type_key, issue_detail in checks:
        if not issue_detail.issue:
            continue
        if type_key in active_types:
            continue

        text = _resolve_template(type_key, issue_detail.detail)
        candidates.append(Suggestion(
            type=type_key,
            text=text,
            priority=issue_detail.severity
        ))

    # ── 3. 按优先级降序，最多取 max_count 条 ──
    candidates.sort(key=lambda s: s.priority, reverse=True)
    return candidates[:max_count]


def _resolve_template(type_key: str, detail: str) -> str:
    """精确匹配 detail 关键词，命中则返回对应文案，否则用 default"""
    for keyword in _TEMPLATES:
        if keyword.startswith(f"{type_key}_") and keyword != f"{type_key}_default":
            suffix = keyword[len(type_key) + 1:]
            if suffix in detail:
                return _TEMPLATES[keyword]
    return _TEMPLATES.get(f"{type_key}_default", "请调整拍摄角度或设置")
