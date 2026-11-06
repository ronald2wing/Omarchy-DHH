# DHH::Dataset: the schema, the content-derived id, the entry and context builders, iteration, append and the sort order.

require 'digest'

module DHH
  module Dataset
    # Strict YYYY-MM-DD; \z rejects a trailing newline (\Z would tolerate one).
    DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/
    POST_KINDS = %w[reply repost quote].freeze
    VERIFIED_TYPES = %w[individual organization government].freeze
    # The keys each entry type requires and allows (`allowed` is required plus
    # optional, precomputed). `kind` and `context` come together, and only on
    # posts.
    SCHEMA = {
      'post' => { required: %w[id text type source], optional: %w[date kind context] },
      'quote' => { required: %w[id text type source], optional: %w[date] },
      'link' => { required: %w[id text type source title domain], optional: %w[date] },
      'video' => { required: %w[id text type source], optional: %w[date] }
    }.transform_values { |keys| keys.merge(allowed: (keys[:required] + keys[:optional]).freeze).freeze }.freeze
    ENTRY_TYPES = SCHEMA.keys.freeze
    CONTEXT_KEYS = %w[author handle text date verified verified_type].freeze

    # Raised by the builders when the entry or context they would return
    # fails validation; the message lists every problem.
    class InvalidEntry < ArgumentError; end

    module_function

    # The dataset id: the first 8 hex digits of the SHA-256 of the normalized
    # text, so the same words always get the same id.
    def id_for(text)
      Digest::SHA256.hexdigest(normalize(text))[0, 8]
    end

    # Every problem with one parsed entry, as strings; empty when it is valid.
    # Cross-line rules (unique sources, sort order) are checked by the
    # callers that see the whole file.
    def validate(entry)
      return ['entry is not an object'] unless entry.is_a?(Hash)

      schema = SCHEMA[entry['type']]
      return ["type must be one of: #{ENTRY_TYPES.join(', ')}"] unless schema

      errors = []
      schema[:required].each { |key| errors << "missing #{key}" unless entry.key?(key) }
      entry.each_key do |key|
        errors << "#{key} is not allowed for type #{entry['type']}" unless schema[:allowed].include?(key)
      end

      text = entry['text']
      if !text.is_a?(String) || text.strip.empty?
        errors << 'text must be non-empty'
      elsif entry['id'] != id_for(text)
        errors << "id must be #{id_for(text)} (derived from the text)"
      end
      errors << 'source must be an https URL' unless entry['source'].is_a?(String) && entry['source'].start_with?('https://')
      errors << 'date must be YYYY-MM-DD' if entry.key?('date') && !date?(entry['date'])
      %w[title domain].each do |key|
        errors << "#{key} must be non-empty" if entry.key?(key) && !present?(entry[key])
      end

      if entry.key?('context')
        errors << "kind must be one of: #{POST_KINDS.join(', ')}" unless POST_KINDS.include?(entry['kind'])
        errors.concat(validate_context(entry['context']))
      elsif entry.key?('kind')
        errors << 'kind requires a context'
      end
      errors
    end

    # Every problem with one context object.
    def validate_context(context)
      return ['context must be an object'] unless context.is_a?(Hash)

      errors = []
      context.each_key { |key| errors << "context.#{key} is not allowed" unless CONTEXT_KEYS.include?(key) }
      errors << 'context.author must be non-empty' unless present?(context['author'])
      errors << 'context.handle must be an @handle' unless handle?(context['handle'])
      errors << 'context.text must be non-empty' if context.key?('text') && !present?(context['text'])
      errors << 'context.date must be YYYY-MM-DD' if context.key?('date') && !date?(context['date'])
      errors << 'context.verified must be true or false' if context.key?('verified') && ![true, false].include?(context['verified'])
      if context.key?('verified_type')
        unless VERIFIED_TYPES.include?(context['verified_type'])
          errors << "context.verified_type must be one of: #{VERIFIED_TYPES.join(', ')}"
        end
        errors << 'context.verified_type requires context.verified' unless context['verified'] == true
      end
      errors
    end

    # A new entry with its content-derived id, keys in the dataset's order and
    # blank keys dropped. Raises InvalidEntry when the result does not
    # validate (an unknown type, a title on a non-link, a kind without a
    # context, ...).
    def entry(type:, text:, source:, date: nil, kind: nil, context: nil, title: nil, domain: nil)
      built = compact(
        'id' => id_for(text), 'type' => type, 'text' => text, 'source' => source,
        'date' => date, 'title' => title, 'domain' => domain, 'kind' => kind, 'context' => context
      )
      check(validate(built))
      built
    end

    # A context object with blank keys dropped; `verified` is stored only
    # when true, so "unverified" and "not known" read the same. Raises
    # InvalidEntry when it does not validate.
    def context(author:, handle:, text: nil, date: nil, verified: false, verified_type: nil)
      built = compact(
        'author' => author, 'handle' => handle, 'text' => text, 'date' => date,
        'verified' => verified == true ? true : nil, 'verified_type' => verified_type
      )
      check(validate_context(built))
      built
    end

    # One dataset line.
    def line(entry)
      "#{JSON.generate(entry)}\n"
    end

    # Yield each parsed entry of the file at `path`; blank lines are skipped.
    def each_entry(path)
      return enum_for(:each_entry, path) unless block_given?

      File.foreach(path) do |raw|
        stripped = raw.strip
        yield JSON.parse(stripped) unless stripped.empty?
      end
    end

    # `lines` sorted: dated entries first (date ascending, id tiebreak),
    # undated entries last (id ascending). Byte-preserving: JSON is parsed only
    # to read the sort keys, and the original lines come back unchanged. Blank
    # lines are dropped.
    def sort_lines(lines)
      keyed = lines.reject { |raw| raw.strip.empty? }.each_with_index.map do |raw, index|
        parsed = JSON.parse(raw)
        dated = parsed['date'].is_a?(String) && !parsed['date'].empty?
        [[dated ? 0 : 1, parsed['date'].to_s, parsed['id'].to_s, index], raw]
      end
      keyed.sort_by(&:first).map(&:last)
    end

    def sorted?(path)
      lines = File.readlines(path, mode: 'rb')
      sort_lines(lines) == lines
    end

    # Sort the file in place. Returns true if it changed. The replacement is
    # atomic: a same-directory temp file renamed over the target, so a crash
    # mid-write leaves the original intact.
    def sort!(path)
      lines = File.readlines(path, mode: 'rb')
      sorted = sort_lines(lines)
      return false if sorted == lines

      tmp = File.join(File.dirname(path), ".#{File.basename(path)}.tmp.#{Process.pid}")
      begin
        File.open(tmp, 'wb', File.stat(path).mode & 0o7777) do |f|
          sorted.each { |raw| f.write(raw) }
        end
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
      true
    end

    # Append entries (Hashes) as dataset lines and sort the file.
    def append(path, entries)
      return if entries.empty?

      File.open(path, 'a') do |f|
        entries.each { |e| f.write(line(e)) }
      end
      sort!(path)
    end

    # Trim, lowercase and collapse ASCII whitespace runs to one space.
    def normalize(text)
      text.to_s.strip.downcase.gsub(/\s+/, ' ')
    end

    def present?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    # "@" and a handle x.com allows (DHH::Avatars owns the handle rule).
    def handle?(value)
      value.is_a?(String) && value.start_with?('@') && DHH::Avatars.valid_handle?(value[1..])
    end

    def date?(value)
      value.is_a?(String) && DATE_PATTERN.match?(value)
    end

    # The hash without nil values and blank strings.
    def compact(hash)
      hash.reject { |_key, value| value.nil? || (value.is_a?(String) && value.strip.empty?) }
    end

    def check(errors)
      raise InvalidEntry, errors.join('; ') unless errors.empty?
    end

    private_class_method :normalize, :present?, :handle?, :date?, :compact, :check
  end
end
