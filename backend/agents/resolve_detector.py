# agents/resolve_detector.py
# 判断当前屏幕上的建议哪些已经被用户解决
# 对比最新视觉结果 + 传感器数据，返回已解决的 suggestion id 列表

from models.request_models import VisionResult, SensorData

_TILT_RESOLVED_THRESHOLD = 3.0   # 倾斜角小于此值认为已水平


def find_resolved(
    active_items: list[dict],   # [{"id": str, "type": str}, ...]
    vision_result: VisionResult,
    sensor_data: SensorData,
) -> list[str]:
    """
    返回已解决的 suggestion id 列表。
    active_items 由 iOS 端传入（active_suggestions 字段），
    但这里我们需要 id → type 的映射，所以 iOS 端也需传入完整列表。
    
    当前实现：根据 type 判断，id 由调用方传入对应关系。
    """
    resolved_types = _compute_resolved_types(vision_result, sensor_data)

    return [
        item["id"]
        for item in active_items
        if item["type"] in resolved_types
    ]


def _compute_resolved_types(
    vision_result: VisionResult,
    sensor_data: SensorData,
) -> set[str]:
    """根据最新分析结果，判断哪些类型的问题已经消失"""
    resolved = set()

    # 光线：问题消失
    if not vision_result.lighting.issue:
        resolved.add("lighting")

    # 构图：问题消失
    if not vision_result.composition.issue:
        resolved.add("composition")

    # 稳定性：问题消失
    if not vision_result.stability.issue:
        resolved.add("stability")

    # 对焦：对焦准确 且 不在对焦中
    if not vision_result.focus.issue and not sensor_data.is_focusing:
        resolved.add("focus")

    # 倾斜：角度回到阈值内
    tilt = (sensor_data.tilt_x ** 2 + sensor_data.tilt_y ** 2) ** 0.5
    if tilt <= _TILT_RESOLVED_THRESHOLD:
        resolved.add("tilt")

    # 其他：问题消失
    if not vision_result.other.issue:
        resolved.add("other")

    return resolved
