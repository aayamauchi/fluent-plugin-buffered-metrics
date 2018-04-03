module Fluent

  class MetricsBackend

    def get_connection_parameters_defaults
      return {}
    end

    def set_connection_parameters(url)
      @connection_parameters = get_connection_parameters_defaults
      return if url.nil? or url.empty?
      url.split(':').each_with_index do |val,i|
        if i == 0
          @connection_parameters['proto'] = val
        elsif i == 1
          @connection_parameters['location'] = val.slice(2..-1)
        elsif i == 2
          @connection_parameters['port'] = val
        end
      end

    end

    def initialize(url = nil)
      @output_buffer = ''
      @socket = nil
      set_connection_parameters(url)
    end

    def connection_open
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
        puts 'we should never be here'
        #$log.error "connection_parameters is not defined"
      end

    end

    def close
      # For now, every possible type of socket has a close method.
      @connection.close
      @connection = nil
    end

    def buffer_flush
      # For now, every possible type of socket has a write method.
      # We also have nothing persistent, so open and closet it.

      @connection.write(@output_buffer)
      @output_buffer = ''
    end

    def buffer?
      not @output_buffer.empty?
    end

    def serialize_entry(entry,time)
      # This _must_ be set in any subclasse.
      nil
    end

    def serialize_array_of_values(data)
      ret_val = ''
      data.each do |e|
        ret_val += serialize_entry(e[0],e[1])
      end
      return ret_val
    end

    def serialize_array_of_hashes(data)
      ret_val = ''
      data.each do |e|
        ret_val += serialize_entry(e,e['time'])
      end
      return ret_val
    end

    def serialize_array(data)
      return ''  if data.empty?
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
      return ret_val
    end

    def buffer_append(data)
      @output_buffer += serialize(data)
    end

    def buffer_append_entry(entry,time)
      @output_buffer += serialize_entry(entry,time)
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
        "%s%s %s %i\n",
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
        "%s%s %s %i\n",
        entry.key?('prefix') ? entry['prefix'] + '.' : '',
        entry['name'],
        ['value'].to_s,
        time
      )
    end

  end

end
