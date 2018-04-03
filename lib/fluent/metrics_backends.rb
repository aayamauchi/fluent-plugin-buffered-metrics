module Fluent

# IN PROGRESS #   class HTTPPOSTSocket
# IN PROGRESS #     # Make a class to add add socket IO methoos for HTTP/HTTPS
# IN PROGRESS #     # POSTs -- # mostly so the output buffer output methods do
# IN PROGRESS #     # not have to conditionally swithc method based on proto.
# IN PROGRESS #
# IN PROGRESS #     require 'net/http'
# IN PROGRESS #
# IN PROGRESS #     def initialize(connection_parameters)
# IN PROGRESS #       @parameters = connection_parameters
# IN PROGRESS #       @headers = @connection_parameters.delete('headers') || {}
# IN PROGRESS #
# IN PROGRESS #       @conn = Net::HTTP.new(@parameters['host'],@parameters['port'])
# IN PROGRESS #       @req = Net::HTTP::Post.new(@parameters['host'],@headers)
# IN PROGRESS #
# IN PROGRESS #       if proto == 'https'
# IN PROGRESS #         require 'net/https'
# IN PROGRESS #         @conn.use_ssl = true
# IN PROGRESS #       end
# IN PROGRESS #     end
# IN PROGRESS #
# IN PROGRESS #     def write(serialized_data)
# IN PROGRESS #       @req.body = serialized_data
# IN PROGRESS #       response = @conn.request(@req)
# IN PROGRESS #       # Wheat do we do, here?
# IN PROGRESS #     end
# IN PROGRESS #
# IN PROGRESS #   end

  class MetricsBackend

    unless method_defined?(:log)
      define_method('log') { $log }
    end

    def get_connection_parameters_defaults
      return {}
    end

    def set_connection_parameters(url)
      @url = url
      @connection_parameters = get_connection_parameters_defaults
      return if @url.nil? or @url.empty?
      @url.split(':').each_with_index do |val,i|
        if i == 0
          @connection_parameters['proto'] = val
        elsif i == 1
          @connection_parameters['location'] = val.slice(2..-1)
        elsif i == 2
          # WORK IN PROGRESS -- we have forgotten to check for a path.
          @connection_parameters['port'] = val
        end
      end

    end

    def initialize(url = nil)
      @output_buffer = []
      @socket = nil
      set_connection_parameters(url)
    end

    def connection_open
      begin
        if @connection_parameters['proto'] == 'tcp'
          @connection = TCPSocket.new(
            @connection_parameters['location'],
            @connection_parameters['port']
          )
        elsif @connection_parameters['proto'] == 'udp'
          @connection = UDPSocket.new(
            @connection_parameters['location'],
            @connection_parameters['port']
          )
        elsif @connection_parameters['proto'] == 'unix'
          @connection = UNIXsocket.new(@connection_parameters['location'])
        elsif @connection_parameters['proto'] == 'file'
          @connection = File.open(@connection_parameters['location'],'a')
        else
          raise ArgumentError, sprintf('Protocol "%s" is not supported',@connection_parameters['proto'])
        end
      rescue ArgumentError => e
        log.error e.message

    end

    def buffer_join(buffer)
      # Allw this to be overridable to facitatte formats such as
      # JSON -- in partficuler, dealing with commas.  The default
      # is EOL delimieted with a trailing EOL

      buffer.join("\n") + "\n"
    end

    def buffer_flush(retries = {})
      retries = { 'max' => 4, 'wait' => 1 }.update(retries)
      # For now, every possible type of socket has a write method.
      # We also have nothing persistent, so open and close it.

      begin
        @connection.open
        @connection.write(buffer_join(@output_buffer))
        @connection.close
      rescue Errno::ETIMEDOUT
        if trial <= @max_retries
          log.warn "out_buffered_metrics: connection timeout to #{@url}. Reconnecting... "
          trial += 1
          connect_client!
          retry
        else
          log.error "out_buffered_metrics: ERROR: connection timeout to #{@url}. Exceeded max_retries #{@max_retries}"
        end
      rescue Errno::ECONNREFUSED
        log.warn "out_buffered_metrics: connection refused by #{@url}"
      rescue SocketError => se
        log.warn "out_buffered_metrics: socket error by #{@url} :#{se}"
      rescue StandardError => e
        log.error "out_buffered_metrics: ERROR: #{e}"
      end

      @output_buffer = []
    end

    def buffer?
      not @output_buffer.empty?
    end

    def serialize_entry(entry,time)
      raise NoMethodError, 'The serialize_entry method has not been specified.'
    end

    def serialize_array_of_values(data)
      data.each do |e|
        @output_buffer << serialize_entry(e[0],e[1])
      end
    end

    def serialize_array_of_hashes(data)
      data.each do |e|
        @output_buffer << serialize_entry(e,e['time'])
      end
    end

    def serialize_array(data)
      return if data.empty?
      if data[0].is_a?(Hash)
        return serialize_array_of_hashes(data)
      elsif data[0].is_a?(Array)
        return serialize_array_of_arrays(data)
      else
        puts 'we should not be here'
      end
    end

    def serialize(data)
      if data.is_a?(Hash)
        return serialize_hash(data)
      elsif data.is_a(Array)
        return serialize_array(data)
      else
        puts 'we should not be here'
      end
    end

    def buffer_append(data)
      @output_buffer << serialize(data)
    end

    def buffer_append_entry(entry,time)
      @output_buffer << serialize_entry(entry,time)
    end

  end

  class MetricsBackendGraphite < MetricsBackend

    def get_connection_parameters_defaults
      return {
        'proto' => 'tcp',
        'location' => 'localhost',
        'port' => 2003
      }
    end

    def serialize_entry(entry,time)
      return sprintf(
        '%s%s %s %i',
        entry.key?('prefix') ? entry['prefix'] + '.' : '',
        entry['name'],entry['value'].to_s,
        time
      )
    end

  end

  class MetricsBackendStatsd < MetricsBackend

    def get_connection_parameters_defaults
      return {
        'proto' => 'udp',
        'location' => 'localhost',
        'port' => 8215
      }
    end

    def serialize_entry(entry,time)
      return sprintf(
        '%s%s %s %i',
        entry.key?('prefix') ? entry['prefix'] + '.' : '',
        entry['name'],
        ['value'].to_s,
        time
      )
    end

  end

end
