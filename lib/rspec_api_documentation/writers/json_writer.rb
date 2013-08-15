require 'rspec_api_documentation/writers/formatter'

module RspecApiDocumentation
  module Writers
    class JsonWriter
      attr_accessor :index, :configuration
      delegate :docs_dir, :to => :configuration

      def initialize(index, configuration)
        self.index = index
        self.configuration = configuration
      end

      def self.write(index, configuration)
        writer = new(index, configuration)
        writer.write
      end

      def write
        File.open(docs_dir.join("index.json"), "w+") do |f|
          f.write Formatter.to_json(JsonIndex.new(index, configuration))
        end
        index.examples.each do |example|
          json_example = JsonExample.new(example, configuration)
          FileUtils.mkdir_p(docs_dir.join(json_example.dirname))
          File.open(docs_dir.join(json_example.dirname, json_example.filename), "w+") do |f|
            f.write Formatter.to_json(json_example)
          end
        end
      end
    end

    class JsonIndex
      def initialize(index, configuration)
        @index = index
        @configuration = configuration
      end

      def sections
        IndexWriter.sections(examples, @configuration)
      end

      def examples
        @index.examples.map { |example| JsonExample.new(example, @configuration) }
      end

      def as_json(opts = nil)
        sections.inject({:resources => []}) do |h, section|
          h[:resources].push(
            :name => section[:resource_name],
            :examples => section[:examples].map { |example|
              {
                :description => example.description,
                :link => "#{example.dirname}/#{example.filename}",
                :groups => example.metadata[:document]
              }
            }
          )
          h
        end
      end
    end

    class JsonExample
      def initialize(example, configuration)
        @example = example
        @host = configuration.curl_host
      end

      def method_missing(method, *args, &block)
        @example.send(method, *args, &block)
      end

      def respond_to?(method, include_private = false)
        super || @example.respond_to?(method, include_private)
      end

      def dirname
        resource_name.downcase.gsub(/\s+/, '_')
      end

      def filename
        basename = description.downcase.gsub(/\s+/, '_').gsub(/[^a-z_]/, '')
        "#{basename}.json"
      end

      def as_json(opts = nil)
        {
          :resource => resource_name,
          :http_method => http_method,
          :route => route,
          :description => description,
          :explanation => explanation,
          :parameters => respond_to?(:parameters) ? parameters : [],
          :requests => requests
        }
      end

      
      def pack_binary(str)
        str.force_encoding("ASCII-8BIT")
        str.strip!
         
        headers, body = str.split("\r\n\r\n")
        if body
          binary, _, after = body.partition("\r\n")
           
          # headers + "\r\n\r\n" + binary.inspect + "\r\n" + after
          headers + "\r\n\r\n" + [binary].pack('m') + "\r\n" + after
        else
          str
        end
      end

      def requests
        super.map do |hash|
          # Jruby -1.9 Enumerable bug workaround
          hash[:response_headers] = hash[:response_headers].to_hash

          if @host
            hash[:curl] = hash[:curl].output(@host) if hash[:curl].is_a? RspecApiDocumentation::Curl
          else
            hash[:curl] = nil
          end

          if hash[:request_body]
            hash[:request_body] = pack_binary(hash[:request_body])
          end
          if hash[:curl]
            hash[:curl] = pack_binary(hash[:curl])
          end

          hash
        end
      end
      
    end
  end
end
