require 'socket'
require 'openssl'
require 'yaml'
require 'monitor'
require 'ruby-debug'
load 'support.rb'

HOST=':((?<nickname>[\S&&[^!]]*)!)?((?<user>\S*)@)?(?<hostname>\S*)?'
COMMAND='(?<command>\w*)'
OPTIONS='(?<options>.*)'
MESSAGE=''

SIMPLE_COMMANDS=[:quit, :part, :notice, :names, :list]

class IRClient
  @config
  @socket
  @disconnect
  @buffers
  @raw
  @cur_buffer
  @motd_msg
  @cur_nick
  attr_accessor :config, :socket, :buffers, :raw, :cur_buffer, :motd_msg

  include IRCSupport::ColoredText
  include IRCSupport::InputHandling
  include IRCSupport::CommandHandling

  def initialize
    begin
      @config = YAML::load_file("config.yaml")
      if @config["ssl"] == true
        @tcp_socket = TCPSocket.new(@config["servername"], @config["port"])
        @context = OpenSSL::SSL::SSLContext.new
        @socket = OpenSSL::SSL::SSLSocket.new(@tcp_socket, @context)
        @socket.sync_close = true
        @socket.connect
      else
        @socket = TCPSocket.open(@config["servername"], @config["port"])
      end
    rescue SocketError => e
      STDERR.puts "Connection problem: #{e}"
      exit 1
    end

    @disconnect = false

    @socket.puts "NICK #{@config['nick']}"
    @socket.puts "USER #{@config['username']} #{@config['usermode']} x : #{@config['realname']}"
    @socket.puts "JOIN #{@config['autojoin']}" unless @config['autojoin'].nil?
    @socket.puts @config["action"]
    @socket.puts "PRIVMSG NickServ :IDENTIFY #{@config['nickserv']}"

    # @raw will store the raw IRC input and output for easy display/logging
    @raw = { :in => Array.new, :out => Array.new }

    # @buffers will be a hash of arrays of messages, and nicks in the channel
    @buffers = {
      :main => {
        :messages => Array.new,
        :nicks    => Array.new,
        :mode     => Array.new,
        :topic    => String.new
      },
      :haus => {
        :messages => Array.new,
        :nicks    => Array.new,
        :mode     => Array.new,
        :topic    => String.new
      }
    }
    @cur_buffer = @cur_nick = "haus"
    socket_lock = Monitor.new

    # Main input loop from user
    write_thread = Thread.new do
      write_loop socket_lock
    end

    # Main input loop from IRC server output to user
    while not @socket.eof and not @disconnect
      read_loop socket_lock
    end

    # Close the socket when done
    @socket.close
  end

  def write_loop lock
    while line = gets
      lock.synchronize do
        parse_lineout line.chomp
      end
    end
  end

  def parse_lineout line
    output = /^(\/(?<command>\w*))?\s*(?<options>.*)?/.match(line)
    if not output[:command].nil? and SIMPLE_COMMANDS.include?(output[:command].downcase.to_sym)
      @socket.print "#{output[:command].upcase} #{output[:options]}\r\n"
    elsif not output[:command].nil? and respond_to?(output[:command].downcase.to_sym)
      send(output[:command].downcase.to_sym, output[:options])
    elsif output[:command].nil?
      send(:msg, "#{@cur_buffer} #{output[:options]}")
    else
      STDERR.puts "Unrecognized command: (COMMAND: #{output[:command]})"
    end
  end

  def read_loop lock
    lock.synchronize do
      # Read lines from the socket
      line = @socket.readline
      parse_linein line.chomp
    end
  end

  def parse_linein line
    input = /^(#{HOST})?\s*#{COMMAND}\s*#{OPTIONS}\s*$/.match(line)
    #puts cyan('^(:((?<nickname>[\S&&[^!]]*)!)?((?<user>\S*)@)?(?<hostname>\S*)?)?\s*(?<command>\w*)\s*(?<options>.*)\s*$')
    if (not input.nil?) and (not input[:command].nil?) and respond_to?(input[:command].downcase.to_sym)
      send(input[:command].downcase.to_sym, input)
    elsif input.nil?
      puts red(line)
      STDERR.puts "Something is broken. #{input.inspect}"
    elsif input[:command].length == 3
      begin
        code = Integer(input[:command].strip)
        if not CODES[code].nil? and respond_to?(CODES[code])
          send(CODES[code], input)
        else
          puts magenta(line)
          puts yellow("Command # #{code} not implemented yet.")
        end
      rescue ArgumentError => e
        STDERR.puts red("#{input[:command]} not an integer")
      end
    else
      puts yellow(line)
      STDERR.puts "Sorry, COMMAND: #{input[:command]} is not implemented."
    end
  end
end

client = IRClient.new
