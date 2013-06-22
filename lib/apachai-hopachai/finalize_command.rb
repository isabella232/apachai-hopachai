module ApachaiHopachai
  class FinalizeCommand < Command
    def self.description
      "Finalize a prepared test"
    end

    def self.help
      puts new([]).send(:option_parser)
    end

    def initialize(*args)
      super(*args)
      @options = {
        :email_from => "Apachai Hopachai CI <#{`whoami`.strip}@localhost>",
        :email_subject => "[%{status}] %{name} (%{before_commit} - %{commit})"
      }
    end

    def start
      require_libs
      parse_argv
      read_and_verify_planset
      save_report
      send_notification
    end

    private

    def require_libs
      require 'safe_yaml'
      require 'ansi2html/main'
      require 'erb'
      require 'stringio'
    end

    def option_parser
      require 'optparse'
      OptionParser.new do |opts|
        nl = "\n#{' ' * 37}"
        opts.banner = "Usage: appa finalize [OPTIONS] PLANSET_PATH"
        opts.separator ""
        
        opts.separator "Options:"
        opts.on("--report FILENAME", String, "Save report to this file instead of into the planset") do |val|
          @options[:report] = val
        end
        opts.on("--email EMAIL", String, "Notify the given email address") do |val|
          @options[:email] = val
        end
        opts.on("--email-from EMAIL", String, "The From address for email notofications. Default: #{@options[:email_from]}") do |val|
          @options[:email_from] = val
        end
        opts.on("--email-subject STRING", String, "The subject for email notofications. Default: #{@options[:email_subject]}") do |val|
          @options[:email_subject] = val
        end
        opts.on("--log-level LEVEL", String, "Set log level. One of: fatal,error,warn,info,debug") do |val|
          set_log_level(val)
        end
        opts.on("--help", "-h", "Show help message") do
          @options[:help] = true
        end
      end
    end

    def parse_argv
      begin
        option_parser.parse!(@argv)
      rescue OptionParser::ParseError => e
        STDERR.puts e
        STDERR.puts
        STDERR.puts "Please see 'appa help finalize' for valid options."
        exit 1
      end

      if @options[:help]
        self.class.help
        exit 0
      end
      if @argv.size != 1
        self.class.help
        exit 1
      end

      @planset_path = File.expand_path(@argv[0])
    end

    def read_and_verify_planset
      abort "The given planset is not complete" if !File.exist?("#{@planset_path}/info.yml")
      @planset_info = YAML.load_file("#{@planset_path}/info.yml", :safe => true)
      if @planset_info['file_version'] != '1.0'
        abort "Plan format version #{@planset_info['file_version']} is unsupported"
      end
      
      @plans = []
      Dir["#{@planset_path}/*.appa-plan"].each do |plan_path|
        if plan_processed?(plan_path)
          @plans << {
            :path   => plan_path,
            :info   => YAML.load_file("#{plan_path}/info.yml", :safe => true),
            :result => YAML.load_file("#{plan_path}/result.yml", :safe => true)
          }
        else
          abort "Plan #{plan_path} has not yet finished processing"
        end
      end
    end

    def plan_processed?(plan_path)
      File.exist?("#{plan_path}/result.yml")
    end

    def save_report
      @info = @planset_info.dup
      @info[:logo] = File.open("#{ROOT}/src/logo.png", "rb") { |f| f.read }
      @info[:passed] = @plans.all? { |plan| plan[:result]['passed'] }

      @plans.each do |plan|
        log = File.open("#{plan[:path]}/output.log", "rb") { |f| f.read }
        html_log = StringIO.new
        ANSI2HTML::Main.new(log, html_log)
        plan[:html_log] = html_log.string
      end
      @jobs = @plans

      template = ERB.new(File.read("#{ROOT}/src/report.html.erb"))
      report   = template.result(binding)
      filename = @options[:report] || "#{@planset_path}/report.html"
      @logger.info "Saving report to #{filename}"
      File.open(filename, "w") do |f|
        f.write(report)
      end
    end

    def send_notification
      if @options[:email]
        subject = @options[:email_subject] % @planset_info
        IO.popen("sendmail -t", "w") do |f|
          f.puts "From: #{@options[:email_from]}"
          f.puts "To: #{@options[:email]}"
          f.puts "Subject: #{subject}"
          f.puts
        end
      end
    end

    def h(text)
      ERB::Util.h(text)
    end
  end
end