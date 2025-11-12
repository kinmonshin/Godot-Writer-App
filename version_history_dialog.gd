## version_history_dialog.gd
## 负责显示和管理文件版本历史的UI对话框。
## 它从 VersionManager 获取数据，并提供预览和恢复功能。
extends Window

# ==============================================================================
# --- 信号定义 ---
# ==============================================================================
## 当用户确认恢复某个版本时发出此信号。
signal version_restored(version_content: String)


# ==============================================================================
# --- 节点引用 (@onready) ---
# ==============================================================================
@onready var version_list: ItemList = %VersionList
@onready var preview_text_edit: TextEdit = %PreviewTextEdit
@onready var restore_button: Button = %RestoreButton
@onready var close_button: Button = %CloseButton


# ==============================================================================
# --- 状态变量 ---
# ==============================================================================
var _current_file_path := ""


# ==============================================================================
# --- Godot 生命周期函数 ---
# ==============================================================================
func _ready() -> void:
	close_requested.connect(hide)
	close_button.pressed.connect(hide)
	restore_button.pressed.connect(_on_restore_button_pressed)
	version_list.item_selected.connect(_on_version_list_item_selected)

# ==============================================================================
# --- 公共 API ---
# ==============================================================================

## 主场景调用此函数来加载和显示指定文件的版本历史。
func load_history_for(file_path: String) -> void:
	_current_file_path = file_path
	_populate_version_list()
	popup_centered()

# ==============================================================================
# --- 内部信号处理 ---
# ==============================================================================

func _on_version_list_item_selected(index: int) -> void:
	if version_list.item_count == 0 or index < 0:
		restore_button.disabled = true
		return

	var version_path = version_list.get_item_metadata(index)
	
	if typeof(version_path) == TYPE_STRING and not version_path.is_empty():
		var file := FileAccess.open(version_path, FileAccess.READ)
		if file:
			preview_text_edit.text = file.get_as_text()
			restore_button.disabled = false
		else:
			preview_text_edit.text = "错误：无法加载版本文件。\n路径: " + version_path
			restore_button.disabled = true
	else:
		preview_text_edit.clear()
		restore_button.disabled = true

func _on_restore_button_pressed() -> void:
	if not preview_text_edit.text.is_empty():
		version_restored.emit(preview_text_edit.text)
		hide()

# ==============================================================================
# --- 核心逻辑 ---
# ==============================================================================

## 填充版本列表的核心函数。
func _populate_version_list() -> void:
	# 1. 清理UI
	version_list.clear()
	preview_text_edit.clear()
	restore_button.disabled = true

	# 2. 获取版本文件
	var file_versions_dir := VersionManager.get_versions_dir_for(_current_file_path)
	var files := DirAccess.get_files_at(file_versions_dir)

	# 3. 解析文件并收集数据
	var temp_versions_data := []
	for file_name in files:
		if file_name.ends_with(".bak"):
			var timestamp_str := file_name.get_basename()
			if not timestamp_str.is_valid_int(): continue
			
			var timestamp := timestamp_str.to_int()
			# [注] 暂时不处理毫秒级时间戳，因为 Time.get_unix_time_from_system() 返回的是秒
			
			var full_path := file_versions_dir.path_join(file_name)
			temp_versions_data.append({ "path": full_path, "timestamp": timestamp })

	# 4. 如果没有版本，显示提示并退出
	if temp_versions_data.is_empty():
		version_list.add_item("没有可用的历史版本。")
		return

	# 5. 排序数据（最新的在最前）
	temp_versions_data.sort_custom(func(a, b): return a.timestamp > b.timestamp)

	# 6. 将排序后的数据填充到 ItemList
	for version_data in temp_versions_data:
		var dt := _get_local_datetime_from_unix(version_data.timestamp)
		var time_str := "%04d-%02d-%02d %02d:%02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
		
		var item_index := version_list.add_item(time_str)
		version_list.set_item_metadata(item_index, version_data.path)

# ==============================================================================
# --- 辅助函数 ---
# ==============================================================================

## 从 UNIX 时间戳获取本地时区的日期时间字典。
func _get_local_datetime_from_unix(unix_timestamp: int) -> Dictionary:
	# Godot 4 的 Time.get_datetime_dict_from_unix_time 默认使用 UTC。
	# 我们需要手动应用时区偏移。
	var utc_offset_seconds: int = Time.get_time_zone_from_system().get("bias", 0) * 60
	return Time.get_datetime_dict_from_unix_time(unix_timestamp + utc_offset_seconds)
