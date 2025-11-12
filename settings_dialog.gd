extends Window

# 节点引用
@onready var font_size_spinbox: SpinBox = %FontSizeSpinBox
@onready var text_color_picker: ColorPickerButton = %TextColorPicker
@onready var bg_color_picker: ColorPickerButton = %BgColorPicker

# _ready() 函数在节点进入场景树时被调用
func _ready() -> void:
	close_requested.connect(hide)

	# 当UI控件的值改变时，调用我们的处理函数
	font_size_spinbox.value_changed.connect(_on_font_size_changed)
	text_color_picker.color_changed.connect(_on_text_color_changed)
	bg_color_picker.color_changed.connect(_on_bg_color_changed)

	# 连接窗口即将弹出的信号到我们的同步函数
	about_to_popup.connect(_on_popup)

# 当窗口即将显示时，这个函数会被调用
func _on_popup() -> void:
	# 从 SettingsManager 获取最新的值，并更新UI控件的显示
	# 这样能确保窗口里的内容永远是最新的
	font_size_spinbox.value = SettingsManager.font_size
	text_color_picker.color = SettingsManager.font_color
	bg_color_picker.color = SettingsManager.bg_color

func _on_font_size_changed(value: float) -> void:
	# 直接调用全局的 SettingsManager 来设置新的字体大小
	SettingsManager.set_font_size(int(value))

func _on_text_color_changed(color: Color) -> void:
	# 直接调用 SettingsManager 来设置新的文本颜色
	SettingsManager.set_text_color(color)

func _on_bg_color_changed(color: Color) -> void:
	# 直接调用 SettingsManager 来设置新的背景颜色
	SettingsManager.set_bg_color(color)

# 当用户点击关闭按钮时，这个函数会被调用
func _on_close_requested() -> void:
	# 只是隐藏窗口，而不是删除它。这样下次可以快速再次显示。
	hide()
