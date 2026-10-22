# Contract test for the plugin's QML: no clipboard-reading text controls.
# Qt 6.12's TextInput/TextField canPaste handler reads the full clipboard text
# on every clipboard change (qquicktextinput.cpp q_canPasteChanged ->
# QMimeData::text()) — an unsolicited, unbounded Wayland read inside the
# shared shell. TextEdit-derived controls check offered formats only, so the
# search field is a single-line TextArea and this guard fails if a reading
# control comes back. Stdlib only.

ROOT = File.expand_path('..', __dir__)
# Instantiations of QQuickTextInput (the family whose canPaste path fetches
# clipboard text on dataChanged). TextEdit-derived editors are allowed.
READING_CONTROL = /\b(TextInput|TextField)\s*\{/

violations = []
panel_text_areas = 0
Dir.glob(File.join(ROOT, '**', '*.qml')).sort.each do |path|
  rel = path.sub("#{ROOT}/", '')
  File.readlines(path).each_with_index do |line, index|
    # Comment mentions are documentation, not instantiations.
    code = line.split('//', 2).first
    violations << "#{rel}:#{index + 1}: #{line.strip}" if code.match?(READING_CONTROL)
    panel_text_areas += 1 if rel == 'Panel.qml' && code.match?(/\bTextArea\s*\{/)
  end
end

raise "FAIL: clipboard-reading text control(s) found:\n#{violations.join("\n")}" unless violations.empty?
raise 'FAIL: the panel search field must be a TextArea' if panel_text_areas.zero?

puts 'test_qml_inputs.rb: all assertions passed'
