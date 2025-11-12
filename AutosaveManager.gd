## AutosaveManager.gd
## 负责处理文件的自动保存逻辑。
## 采用混合触发机制：定期保存 + 不活动时保存。
## 在每次保存前，会通知 VersionManager 创建版本历史。
extends Node

## 每隔多少秒强制保存一次。
const REGULAR_SAVE_INTERVAL: float = 60.0
## 用户停止输入多少秒后，触发不活动保存。
const INACTIVITY_SAVE_DELAY: float = 3.0

# 内部状态变量，以下划线开头表示其主要供内部使用
var _autosave_timer: Timer
var _inactivity_timer: Timer
var _current_text_content := ""
var _current_file_path := ""
var _is_dirty := false # 标记自上次自动保存以来，内容是否有变化

func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "RegularAutosaveTimer" # 给节点命名是个好习惯
	_autosave_timer.wait_time = REGULAR_SAVE_INTERVAL
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(save_current_file)
	add_child(_autosave_timer)

	_inactivity_timer = Timer.new()
	_inactivity_timer.name = "InactivityAutosaveTimer"
	_inactivity_timer.wait_time = INACTIVITY_SAVE_DELAY
	_inactivity_timer.one_shot = true
	_inactivity_timer.timeout.connect(save_current_file)
	add_child(_inactivity_timer)

# ==============================================================================
# --- 公共 API ---
# ==============================================================================

## 主场景在文本改变时调用此函数，以更新内容并触发不活动计时器。
## @param text: String - 当前 TextEdit 的完整内容。
## @param path: String - 当前打开文件的路径。
func update_content(text: String, path: String) -> void:
	if text != _current_text_content:
		_current_text_content = text
		_current_file_path = path
		_is_dirty = true
		_inactivity_timer.start() # 重置不活动计时器

## 主场景在应用退出前调用此函数，以执行最后一次强制保存。
func perform_final_save() -> void:
	# 停止计时器，防止在退出过程中再次触发保存，导致竞态条件
	_autosave_timer.stop()
	_inactivity_timer.stop()
	save_current_file()

# ==============================================================================
# --- 核心保存逻辑 ---
# ==============================================================================

## 执行核心的保存操作。
## 1. 创建版本备份。 2. 覆盖写入原始文件。
func save_current_file() -> void:
	if not _is_dirty or _current_file_path.is_empty():
		return
	
	if _current_file_path.begins_with("res://"):
		printerr("AutosaveManager: Skipped saving to read-only project path: ", _current_file_path)
		return

	# [关键集成点] 在写入文件【之前】，先为当前状态创建版本
	VersionManager.create_version_for(_current_file_path)

	print("AutosaveManager: Autosaving to ", _current_file_path)
	
	var file := FileAccess.open(_current_file_path, FileAccess.WRITE)
	if file:
		file.store_string(_current_text_content)
		_is_dirty = false # 保存后，重置“脏”标记
	else:
		var error := FileAccess.get_open_error()
		printerr("AutosaveManager: Error saving file %s. Code: %d" % [_current_file_path, error])
