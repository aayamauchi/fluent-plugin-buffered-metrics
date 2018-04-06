module Fluent

  class SocketLike
    # Just a little something to try to make any possible output
    # bakced act like a socket so we don't have to check the type
    # and change method colls throughout the code.

    def open
      if @parameters.nil? or @parameters.empty?
        raise RuntimeError, "SocketLike open called with no parameters set"
      else
        if @parameters['proto'] == 'tcp'
          @socket = TCPSocket.new(
            @parameters['host'],
            @parameters['port']
          )
        elsif @parameters['proto'] == 'udp'
          @socket = UDPSocket.new(
            @parameters['host'],
            @parameters['port']
          )
        elsif @parameters['proto'] == 'unix'
          @socket = UNIXsocket.new(@parameters['path'])
        elsif @parameters['proto'] == 'file'
          @socket = File.new(@parameters['path'],'a')
        elsif @parameters['proto'] =~ /^http/
          @socket = Net::HTTP.new(@parameters['host'],@parameters['port'])
          @socket.use_ssl = @parameters['proto'] == 'https'
        else
          raise ArgumentError, 'SocketLike class does not support protocol' + @parameters['proto']
        end
      end
    end

    def write(string)
      if @parameters['proto'] =~ /^http/
        req = Net::HTTP::Post.new(@parameters['path'])
        req.body = string
        @parameters['headers'].each do |h|
          req.add_field(h[0],h[1])
        end
        #@socket.request(req) or raise IOError "Error writing to backend"
        @socket.request(req)
      else
        #@socket.write(string) or raise IOError "Error writing to backend"
        @socket.write(string)
      end
    end

    def close
      if @parameters['proto'] =~ /^http/
        @socket.finish
      else
        @socket.close
      end
    end

    def initialize(parameters)
      @parameters = parameters
      # Is this actually needed here?
      @socket = nil
      if @parameters['proto'] =~ /^http/
        require 'net/http'
        require 'net/https' if @paramters['proto'] == 'https'
      end
    end

  end

  class MetricsBackend

    def get_connection_parameters_defaults
      # This should be overriden in any any subclass.
      return {}
    end

    def set_connection_parameters(url,headers = [])
      @connection_parameters.merge!(get_connection_parameters_defaults)
      @connection_parameters.merge!(
        Hash[['proto','host','port','path'].zip(
          url.match(/^([^:]*):\/\/([^:\/]*):?(\d*)(\/.*)?/).to_a.map {|e| e.nil? or e.empty? ? nil : e }[1..-1]
        )]
      ) unless url.nil? or url.empty?
      @connection_parameters['headers'] ||= []
      @connection_parameters['headers'] += headers
    end

    def get_connection_parameters
      @connection_parameters
    end

    def initialize(url = nil,headers = [])
      @output_buffer = []
      @connection_parameters = {}
      set_connection_parameters(url, headers)
      @connection = SocketLike.new(@connection_parameters)
    end

    def buffer_dump
      # Allw this to be overridable to facitatte formats such as
      # multiliine formats, or things JSON where there are
      # punctuation differences depending upon position.
      @output_buffer.join("\n") + "\n"
    end

    def buffer_flush

      begin
        @connection.open
        @connection.write(buffer_dump)
      rescue
        raise
      ensure
        @connection.close
      end

      @output_buffer = []
    end

    def buffer?
      not @output_buffer.empty?
    end

    def serialize_entry(entry,time)
      raise NoMethodError, 'The serialize_entry method has not been specified.'
    end

    def serialize_array(data)
      return if data.empty?
      if data[0].is_a?(Hash)
        return serialize_array_of_hashes(data)
      elsif data[0].is_a?(Array)
        return serialize_array_of_arrays(data)
      else
        raise ArgumentError, 'serialize_array method input must be of Hash or Array type'
      end
    end

    def serialize(data)
      if data.is_a?(Hash)
        return serialize_hash(data)
      elsif data.is_a(Array)
        return serialize_array(data)
      else
        raise ArgumentError, 'serialize method input must be of Hash or Array type'
      end
    end

    def buffer_append_array_of_values(data)
      @output_buffer += data.map {|e| serialize_entry(e[0],e[1]) }
    end

    def buffer_append_array_of_hashes(data)
      @output_buffer += data.map {|e| serialize_entry(e,e['time']) }
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
      return { 'proto' => 'tcp', 'host' => 'localhost', 'port' => 2003 }
    end

    def serialize_entry(entry,time)
      if entry.is_a?(Hash) and entry.key?('name') and entry['name'].is_a?(String) and entry.key?('value') and entry['value'].is_a?(Numeric) and time.is_a?(Numeric)
        return sprintf(
          '%s%s %s %i',
          entry.key?('prefix') ? entry['prefix'] + '.' : '',
          entry['name'],entry['value'].to_s,
          time.to_i
        )
      end
    end

  end

  class MetricsBackendStatsd < MetricsBackend

    def get_connection_parameters_defaults
      return { 'proto' => 'udp', 'host' => 'localhost', 'port' => 8215 }
    end

    def serialize_entry(entry,time)
      if entry.is_a?(Hash) and entry.key?('name') and entry['name'].is_a?(String) and entry.key?('value') and entry['value'].is_a?(Numeric) and time.is_a?(Numeric)
        return sprintf(
          '%s%s:%s|c',
          entry.key?('prefix') ? entry['prefix'] + '.' : '',
          entry['name'],
          entry['value'].to_i
        )
      end
    end

  end

end
