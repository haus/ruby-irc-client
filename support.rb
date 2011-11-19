class IRCSupport
  module ColoredText
    def colorize(text, color_code)
      "\e[#{color_code}m#{text}\e[0m"
    end

    def red(text); colorize(text, 31); end
    def green(text); colorize(text, 32); end
    def yellow(text); colorize(text, 33); end
    def blue(text); colorize(text, 34); end
    def magenta(text); colorize(text, 35); end
    def cyan(text); colorize(text, 36); end
  end

  module InputHandling
    CODES = Array.new(1000)
    CODES[1] = CODES[2] = CODES[3] = CODES[4] = CODES[5] = :welcome
    CODES[251] = CODES[252] = CODES[253] = CODES[254] =CODES[255] = CODES[265] = CODES[266] = :lusers
    CODES[332] = CODES[333] = :topic
    CODES[321] = CODES[322] = CODES[323] = :list
    CODES[353] = CODES[366] = :names
    CODES[372] = CODES[375] = CODES[376] = :motd
    CODES[432] = :err

    def welcome(options)
      puts /(?<to>\w*)\s*:?(?<message>.*)$/.match(options[:options])[:message]
    end

    def quit(options)
      message = "#{options[:nickname]} has quit (#{options[:options].gsub(':','')})"
      @buffers[@cur_buffer.to_sym][:messages] << message
      puts message
    end

    def lusers(options)
      case options[:command]
        when /25[234]/
          lusers_data = /(?<to>\w*)\s*(?<message>.*)$/.match(options[:options])
          lusers_msg = /(?<int>\d*)\s*:(?<message>.*)$/.match(lusers_data[:message]) unless lusers_data[:message].nil?
          puts "#{lusers_msg[:int]} #{lusers_msg[:message]}"
        when /(25[15]|26[56])/
          lusers_data = /(?<to>\w*)\s*:(?<message>.*)$/.match(options[:options])
          puts lusers_data[:message]
      end
    end

    def privmsg(options)
      from = options[:nickname]
      message = options[:options]
      target = message.shift_word.gsub(':','').strip
      puts "from: #{from}, message: #{message}, target: #{target}"
      puts "#{message} to #{target} from #{from}"
      @buffers[target.to_sym] = {
        :messages => Array.new,
        :nicks    => Array.new,
        :mode     => Array.new,
        :topic    => String.new
      }
      @buffers[target.to_sym][:messages] << message
    end

    def motd(options)
      motd_data = /(?<to>\w*)\s*:(?<message>.*)$/.match(options[:options])
      case options[:command]
        when "372"
          @motd_msg << motd_data[:message] + "\n"

        when "375"
          @motd_msg = motd_data[:message].nil? ? String.new : motd_data[:message] + "\n"
        when "376"
          @motd_msg << motd_data[:message]
          puts @motd_msg
      end
    end

    def ping(options)
      options[:options].gsub!(":","") unless options[:options].nil?
      @socket.print "PONG #{options[:options]}"
    end

    def mode(options)
      # Ignore mode for now. Implement later.
    end

    def error(options)
      @disconnect = true
      puts "Exiting"
    end

  end

  module CommandHandling
    # Join technically falls into two categories, but it's placed here
    def join(options)
      case caller[0][/`.*'/][1..-2]
        when /parse_lineout/
          join_opts = options.split(' ')
          channels = join_opts[0].split(',')
          keys = join_opts[1].split(',') unless join_opts.length < 2
          send(:buffer, channels.first)
          @socket.print "JOIN #{options}\r\n"
        when /parse_linein/
          
        else
          puts yellow("JOIN got called from an unexpected context.")
      end
    end

    # Notice also falls into two categories
    def notice(options)
      case caller[0][/`.*'/][1..-2]
        when /parse_lineout/
          @socket.print "NOTICE #{options}\r\n"
        when /parse_linein/
          notice_data = /(?<to>\w*)\s*:(?<message>.*)$/.match(options[:options])
          from = "#{options[:nickname].nil? ? nil : options[:nickname] + '!'}#{options[:user].nil? ? nil : options[:user] + '@'}#{options[:hostname]}"
          to = notice_data[:to].strip
          message = notice_data[:message].strip
          @buffers[@cur_buffer.to_sym][:messages] << "NOTICE to #{to} from '#{from}': '#{message}'"
          puts "NOTICE to #{to} from '#{from}': '#{message}'"
        else
          puts yellow("NOTICE got called from an unexpected context.")
      end
    end

    # Also called from two contexts
    def nick(options)
      case caller[0][/`.*'/][1..-2]
        when /parse_lineout/
          @socket.print "NICK #{options}\r\n"
        when /parse_linein/
          puts "#{options[:nickname]} changed nickname to #{options[:options].gsub(':','')}"
        else
          puts yellow("NICK got called from an unexpected context.")
      end
    end

    def me(options)
      @socket.print "PRIVMSG #{@cur_buffer} \x01ACTION #{options}\x01\r\n"
    end

    def msg(options)
      @socket.print "PRIVMSG #{options.shift_word} #{options}\r\n"
    end

    # These methods implement commands that don't match to irc commands exactly
    def buffer(options)
      if options == @cur_buffer
        # Changing to the cur_buffer is a noop.
      elsif options.empty?
        puts green("Current buffer is '#{@cur_buffer}'")
      elsif @buffers.has_key?(options.to_sym)
        @cur_buffer = options
      else
        @buffers[options.to_sym] = {
          :messages => Array.new,
          :nicks    => Array.new,
          :mode     => Array.new,
          :topic    => String.new
        }
        @cur_buffer = options
        STDERR.puts red("Buffer '#{options}' did not exist.")
      end
    end
  end
end

class String
  @@first_word_re = /^([\w||\#]+\W*)/

  def shift_word
    return nil if self.empty?
    self=~@@first_word_re
    newself= $' || ""       # $' is POSTMATCH
    self.replace(newself) unless $'.nil?
    $1
  end
end
