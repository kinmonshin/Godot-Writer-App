## search_panel.gd
## 负责查找与替换面板的UI交互。
## 收集用户输入，并通过信号将查找/替换指令发送给主场景。
extends PanelContainer

# ==============================================================================
# --- 信号定义 ---
# ==============================================================================
signal search_requested(text: String, flags: int, direction: int)
signal replace_requested(replace_text: String)
signal replace_all_requested(find_text: String, replace_text: String, flags: int)
signal search_text_changed()
signal panel_closed()


# ==============================================================================
# --- 节点引用 (@onready) ---
# ==============================================================================
@onready var search_line_edit: LineEdit = %SearchLineEdit
@onready var replace_line_edit: LineEdit = %ReplaceLineEdit
@onready var match_case_check: CheckBox = %MatchCaseCheck
@onready var whole_words_check: CheckBox = %WholeWordsCheck
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var replace_button: Button = %ReplaceButton
@onready var replace_all_button: Button = %ReplaceAllButton
@onready var close_button: Button = %CloseButton


# ==============================================================================
# --- Godot 生命周期函数 ---
# ==============================================================================
func _ready() -> void:
	# --- 连接内部UI控件的信号 ---
	search_line_edit.text_changed.connect(_on_search_text_changed)
	search_line_edit.text_submitted.connect(_on_next_button_pressed) # 在输入框按回车 = 查找下一个
	
	previous_button.pressed.connect(_on_previous_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)
	replace_button.pressed.connect(_on_replace_button_pressed)
	replace_all_button.pressed.connect(_on_replace_all_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)

# ==============================================================================
# --- 公共 API ---
# ==============================================================================

## 主场景在显示此面板后调用，以将焦点设置到输入框。
func grab_focus_on_line_edit() -> void:
	search_line_edit.grab_focus()
	search_line_edit.select_all()

# ==============================================================================
# --- 内部信号处理 ---
# ==============================================================================

func _on_search_text_changed(new_text: String) -> void:
	search_text_changed.emit()

func _on_previous_button_pressed() -> void:
	_emit_search_requested(-1)

func _on_next_button_pressed() -> void:
	_emit_search_requested(1)

func _on_replace_button_pressed() -> void:
	replace_requested.emit(replace_line_edit.text)

func _on_replace_all_button_pressed() -> void:
	var find_text := search_line_edit.text
	if find_text.is_empty():
		return

	var flags := _get_current_search_flags()
	replace_all_requested.emit(find_text, replace_line_edit.text, flags)

func _on_close_button_pressed() -> void:
	hide()
	panel_closed.emit()

# ==============================================================================
# --- 辅助函数 ---
# ==============================================================================

## 统一处理查找请求的信号发射。
func _emit_search_requested(direction: int) -> void:
	var text_to_find := search_line_edit.text
	if text_to_find.is_empty():
		return

	var flags := _get_current_search_flags()
	search_requested.emit(text_to_find, flags, direction)

## 从复选框中计算当前的查找标志。
func _get_current_search_flags() -> int:
	var flags := 0
	if match_case_check.button_pressed:
		flags |= TextEdit.SEARCH_MATCH_CASE
	if whole_words_check.button_pressed:
		flags |= TextEdit.SEARCH_WHOLE_WORDS
	return flags
