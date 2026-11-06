# Contract checks over the QML, its assets and helpers, the source text and the manifest.

require_relative 'test_helper'

CLIPBOARD_READING_CONTROL_RE = /\b(TextInput|TextField)\s*\{/

qml_files = Dir.glob(File.join(ROOT, '**', '*.qml')).sort
rel = ->(path) { path.sub("#{ROOT}/", '') }

# 1. No clipboard-reading control; the single search field is one TextArea.
# Qt 6.12's TextInput/TextField read the full clipboard on every clipboard
# change; TextEdit-derived controls check offered formats only.
violations = []
qml_files.each do |path|
  File.readlines(path).each_with_index do |line, index|
    code = line.split('//', 2).first
    violations << "#{rel.call(path)}:#{index + 1}: #{line.strip}" if code.match?(CLIPBOARD_READING_CONTROL_RE)
  end
end
assert(violations.empty?, "clipboard-reading text control(s) found:\n#{violations.join("\n")}")

search_fields = Dir.glob(File.join(ROOT, '**', 'SearchField.qml'))
assert(search_fields.size == 1, "exactly one SearchField.qml (found #{search_fields.map(&rel).inspect})")
search_field = File.read(search_fields.first)
text_areas = search_field.lines.count { |line| line.split('//', 2).first.match?(/\bTextArea\s*\{/) }
assert(text_areas == 1, 'the search field is a single TextArea')
assert(search_field.include?('readonly property int maxLength') && search_field.include?('onTextChanged:'),
       'the search field bounds the query on every edit path, not only on Ctrl+V')

# 2. Icon names resolve. Look.icon(name, hoverVariant) builds "<name>.svg"
# or "<name>-hover.svg" from the names used across the UI: DiscButton's
# `icon: "x"` and Icon's `name: "x"`.
icons = Dir.glob(File.join(ROOT, 'assets', 'icons', '*.svg')).map { |p| File.basename(p, '.svg') }
referenced = qml_files.flat_map { |p| File.read(p).scan(/\bicon: "([a-z-]+)"/).flatten }
referenced += qml_files.flat_map { |p| File.read(p).scan(/\bname: "([a-z-]+)"/).flatten }
assert(referenced.include?('search') && referenced.include?('folder'), 'the icon scan sees Icon and DiscButton names')
referenced.uniq.each do |name|
  assert(icons.include?(name), "icon exists: assets/icons/#{name}.svg")
end
%w[grok dots bookmark share folder reply repost like views].each do |name|
  assert(icons.include?("#{name}-hover"), "hover variant exists: assets/icons/#{name}-hover.svg")
end

# 3. Every asset literal resolves from its file's directory, and every asset
# is used by code, so a dead one fails. A file counts as used when its file
# name appears in the QML or js/; an icon also counts when its name (less
# any -hover suffix) is a string literal there, since Look.icon builds the
# file name from it (Format.sealIconName returns the seal names from
# js/format.mjs).
qml_files.each do |path|
  File.read(path).scan(%r{"((?:\.\./)*assets/[^"]+\.(?:svg|png))"}).flatten.uniq.each do |ref|
    target = File.expand_path(ref, File.dirname(path))
    assert(File.file?(target), "#{rel.call(path)}: asset exists: #{ref}")
  end
end
code_sources = (qml_files + Dir.glob(File.join(ROOT, 'js', '*.mjs'))).map { |p| File.read(p) }
Dir.glob(File.join(ROOT, 'assets', '**', '*')).select { |p| File.file?(p) }.sort.each do |path|
  file_name = File.basename(path)
  used = code_sources.any? { |src| src.include?(file_name) }
  if !used && rel.call(path).start_with?('assets/icons/')
    name = File.basename(path, '.svg').delete_suffix('-hover')
    used = code_sources.any? { |src| src.include?("\"#{name}\"") }
  end
  assert(used, "#{rel.call(path)} is used by the QML or js/")
end

# 4. Every Qt.resolvedUrl("<rel>") literal, and every `source: "<rel>.mjs"`
# (the WorkerScript entry), resolves from its file's directory.
resolved = []
qml_files.each do |path|
  src = File.read(path)
  refs = src.scan(/Qt\.resolvedUrl\("([^"]+)"\)/).flatten + src.scan(/source:\s*"([^"]+\.mjs)"/).flatten
  refs.uniq.each do |ref|
    resolved << rel.call(path)
    target = File.expand_path(ref, File.dirname(path))
    assert(File.exist?(target), "#{rel.call(path)}: resolved target exists: #{ref}")
  end
end
assert(resolved.any? { |f| f.start_with?('model/') }, 'the resolved-path scan covers model/')

# 5. Every `helper: "<name>"` literal names an executable helpers/<name>
# (HelperProcess resolves it as ../helpers/<name>), and every helper is named
# by one, so an unused helper fails.
helpers = qml_files.flat_map { |p| File.read(p).scan(/\bhelper:\s*"([a-z-]+)"/).flatten }.uniq
assert(helpers.any?, 'the helper scan found literals')
helpers.each do |name|
  target = File.join(ROOT, 'helpers', name)
  assert(File.file?(target) && File.executable?(target), "helper exists and is executable: helpers/#{name}")
end
Dir.glob(File.join(ROOT, 'helpers', '*')).map { |p| File.basename(p) }.each do |name|
  assert(helpers.include?(name), "helpers/#{name} is run through a helper: literal")
end
helper_process = File.read(File.join(ROOT, 'model', 'HelperProcess.qml'))
assert(helper_process.include?('Qt.resolvedUrl("../helpers/" + root.helper)'), 'HelperProcess resolves helpers under helpers/')
max_handles = File.read(File.join(ROOT, 'helpers', 'fetch-avatars'))[/MAX_HANDLES = (\d+)/, 1]
max_batch = File.read(File.join(ROOT, 'model', 'AvatarCache.qml'))[/property int maxBatch: (\d+)/, 1]
assert(max_handles && max_handles == max_batch, "AvatarCache.maxBatch (#{max_batch.inspect}) is fetch-avatars' MAX_HANDLES (#{max_handles.inspect})")

# 6. Every directory with a qmldir lists exactly its .qml files (once a
# directory has one, an unlisted type there no longer resolves), and a file
# is declared `singleton` there exactly when it starts with `pragma Singleton`.
qmldirs = Dir.glob(File.join(ROOT, '**', 'qmldir'))
assert(qmldirs.map(&rel).sort == %w[model/qmldir ui/base/qmldir], "the qmldir scan found model/ and ui/base/ (found #{qmldirs.map(&rel).sort.inspect})")
qmldirs.each do |qmldir|
  dir = File.dirname(qmldir)
  entries = File.readlines(qmldir).map(&:split).reject(&:empty?)
  listed = entries.map(&:last)
  on_disk = Dir.glob(File.join(dir, '*.qml')).map { |p| File.basename(p) }
  assert(listed.sort == on_disk.sort, "#{rel.call(qmldir)} lists exactly #{on_disk.sort.inspect} (lists #{listed.sort.inspect})")
  assert(listed.uniq.size == listed.size, "#{rel.call(qmldir)} lists each file once")
  entries.each do |entry|
    assert(File.basename(entry.last, '.qml') == entry[-3], "#{rel.call(qmldir)}: type #{entry[-3]} is its file's name (#{entry.last})")
  end
end
singletons = qml_files.select { |path| File.readlines(path).first.to_s.chomp == 'pragma Singleton' }
assert(singletons.map(&rel).sort == %w[model/Desktop.qml ui/base/Look.qml], "the singleton scan found Desktop and Look (found #{singletons.map(&rel).sort.inspect})")
qml_files.each do |path|
  qmldir = File.join(File.dirname(path), 'qmldir')
  next unless File.file?(qmldir)

  name = File.basename(path, '.qml')
  declared = File.readlines(qmldir).map(&:split).include?(['singleton', name, '1.0', "#{name}.qml"])
  assert(declared == singletons.include?(path),
         "#{rel.call(path)}: declared a singleton in its qmldir exactly when it starts with pragma Singleton")
end
singletons.each { |path| assert(File.file?(File.join(File.dirname(path), 'qmldir')), "#{rel.call(path)} has a qmldir to declare it") }

# 7. Every file starts with `pragma ComponentBehavior: Bound` (after
# `pragma Singleton` in a singleton), so delegates read only what they
# declare.
qml_files.each do |path|
  lines = File.readlines(path).map(&:chomp)
  lines.shift if singletons.include?(path)
  assert(lines.first == 'pragma ComponentBehavior: Bound', "#{rel.call(path)} starts with pragma ComponentBehavior: Bound")
end

# 8. Layer rules: only model/ does I/O, starts programs or writes the
# clipboard (model/Desktop.qml for the last two), except the renderer saving
# its grab, and model/ draws nothing.
qml_files.each do |path|
  code = File.read(path).lines.map { |line| line.split('//', 2).first }.join
  if rel.call(path).start_with?('model/')
    assert(!code.match?(/\b(Rectangle|Text|Image)\s*\{/), "#{rel.call(path)}: model/ holds no visual items")
  else
    assert(!code.match?(/\b(Process|FileView|WorkerScript)\s*\{/), "#{rel.call(path)}: only model/ runs processes, files or workers")
    assert(!code.match?(/\bexecDetached\b/), "#{rel.call(path)}: only model/ starts programs (Desktop)")
    assert(!code.match?(/\bclipboardText\s*=(?!=)/), "#{rel.call(path)}: only model/ writes the clipboard (Desktop)")
  end
end
desktop = File.read(File.join(ROOT, 'model', 'Desktop.qml'))
assert(desktop.include?('execDetached') && desktop.match?(/\bclipboardText\s*=(?!=)/), 'the layer scan matches what Desktop does')

# 9. No invisible characters written literally (zero-width space and joiner,
# word joiner, variation selector, BOM, the noncharacters U+FFFE and U+FFFF)
# in any source, script, test or doc: they are spelled as \u escapes, so a
# reader can see them. The dataset (data/entries.jsonl) is not scanned: it
# holds post text exactly as published.
INVISIBLE_RE = /[\u200B-\u200D\u2060\uFE0E\uFE0F\uFEFF\uFFFE\uFFFF]/
text_sources = %w[**/*.qml **/qmldir js/* dev/* tests/js/* lib/**/*.rb helpers/* tools/* tests/ruby/*.rb tests/run *.md **/*.json]
               .flat_map { |pattern| Dir.glob(File.join(ROOT, pattern)) }
               .select { |path| File.file?(path) }.uniq.sort
assert(text_sources.any? { |path| rel.call(path).start_with?('dev/') } && text_sources.any? { |path| rel.call(path).end_with?('.md') },
       'the invisible-character scan covers dev/ and the docs')
text_sources.each do |path|
  File.readlines(path, encoding: 'UTF-8').each_with_index do |line, index|
    assert(!line.match?(INVISIBLE_RE), "#{rel.call(path)}:#{index + 1}: literal invisible character; write it as a \\u escape")
  end
end

# 10. The manifest parses and its entry point exists.
manifest = JSON.parse(File.read(File.join(ROOT, 'manifest.json')))
assert(File.file?(File.join(ROOT, manifest.dig('entryPoints', 'barWidget'))), 'manifest entry point exists')

# 11. Every Look property and function is used: read as `Look.<name>` outside
# Look.qml, or named in the declaration of another Look member that is used
# (a measured part of a composed value, such as repostLabelLead in
# repostHeaderIndent). A token nothing reads fails.
look_path = File.join(ROOT, 'ui', 'base', 'Look.qml')
look_code = File.readlines(look_path).map { |line| line.split('//', 2).first }
declaration_re = /^\s*(?:readonly\s+)?(?:property\s+\w+\s+(\w+)|function\s+(\w+)\s*\()/
declarations = {}
current = nil
look_code.each do |line|
  if (match = line.match(declaration_re))
    current = match[1] || match[2]
    declarations[current] = +''
  end
  declarations[current] << line if current
end
assert(declarations.size > 50 && declarations.key?('icon') && declarations.key?('columnWidth'),
       'the Look scan sees its properties and functions')
outside = (qml_files - [look_path]).map { |path| File.read(path) }.join("\n")
used = declarations.keys.select { |name| outside.match?(/\bLook\.#{name}\b/) }
loop do
  bodies = used.map { |name| declarations[name] }.join("\n")
  more = (declarations.keys - used).select { |name| bodies.match?(/\b#{name}\b/) }
  break if more.empty?

  used += more
end
(declarations.keys - used).each { |name| assert(false, "Look.#{name} is read by nothing") }

puts 'test_contracts.rb: all assertions passed'
