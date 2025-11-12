extends Node

# ==============================================================================
# --- 常量与信号 ---
# ==============================================================================
const SETTINGS_FILE_PATH := "user://settings.cfg"

# 当设置值发生变化时，我们会发出这些信号
# 任何关心这些变化的节点都可以监听它们
signal font_size_changed(new_size: int)
signal text_color_changed(new_color: Color)
signal bg_color_changed(new_color: Color)


# ==============================================================================
# --- 状态变量 ---
# ==============================================================================
# 这些变量是我们的“单一数据源”，存储着当前应用的设置状态
var font_size: int = 16
var font_color: Color = Color.BLACK
var bg_color: Color = Color.WHITE


# ==============================================================================
# --- 公共方法 (API) ---
# ==============================================================================
# 这里是未来其他脚本（如 settings_dialog.gd）与这个管理器交互的入口
func set_font_size(new_size: int):
	if font_size == new_size: return # 如果值没变，就什么都不做
	font_size = new_size
	font_size_changed.emit(new_size)
	save_settings() # 每次修改后自动保存

func set_text_color(new_color: Color):
	if font_color == new_color: return
	font_color = new_color
	text_color_changed.emit(new_color)
	save_settings()

func set_bg_color(new_color: Color):
	if bg_color == new_color: return
	bg_color = new_color
	bg_color_changed.emit(new_color)
	save_settings()


# ==============================================================================
# --- 数据持久化 ---
# ==============================================================================
func save_settings() -> void:
	var config := ConfigFile.new()

	# 从自身的变量中获取数据
	config.set_value("display", "font_size", font_size)
	config.set_value("display", "font_color", font_color)
	config.set_value("display", "bg_color", bg_color)

	config.save(SETTINGS_FILE_PATH)

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) == OK:
		# 加载数据到自身的变量
		font_size = config.get_value("display", "font_size", 16) as int
		font_color = config.get_value("display", "font_color", Color.BLACK) as Color
		bg_color = config.get_value("display", "bg_color", Color.WHITE) as Color

	# 加载完成后，发出信号通知整个应用更新
	font_size_changed.emit(font_size)
	text_color_changed.emit(font_color)
	bg_color_changed.emit(bg_color)
