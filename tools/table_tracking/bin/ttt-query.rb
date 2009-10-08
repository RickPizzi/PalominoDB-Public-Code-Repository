# == Synopsis
#
# ttt-query: Generate a report about tracked tables
#
# == Usage
#
# ttt-query [-h] -c config.yml -o text
#
# -h, --help:
#    This help
# --config file, -c file:
#    Path to ttt config file.
# --output type, -o type:
#    Specifies an output formatter.
#    One of:
#        email
#        text
#        nagios
# --debug:
#    Make the query tool VERY noisy about what it's doing.
# --since <timespec>, -s <timespec>:
#    Where <timespec> is something like:
#        last-collect (since the last collector run)
#        4h (4 hours)
#        1d (1 day)
#        1w (1 week)
#        
# --where <clause>, -w <clause>:
#    Cannot presently be specified when 'last-collect' is used with --since.
#    Can be specified multiple times.
#    Allows you to place contraints based on columns.
#    Constraints are any valid sql fragment.
#    Recognized columns for syntax tracking:
#        server
#        database_name
#        table_name
#        created_at
#        updated_at
#        run_time (when the collection ran. --since takes precedence over this)
#        create_syntax
#    Recognized columns for volume tracking:
#        server
#        database_name
#        table_name
#        created_at (when the collection ran. --since takes precedence )
#        updated_at (should always be equal to the above)
#        kbytes (size of the table)
#
require 'rubygems'
require 'ttt/db'
require 'yaml'
require 'getoptlong'
require 'rdoc/usage'
require 'pp'
require 'ttt/formatters'
require 'ttt/format/text'
#require 'ttt/format/email'
#require 'ttt/format/nagios'

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
  [ '--config', '-c', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--output', '-o', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--debug', GetoptLong::NO_ARGUMENT ],
  [ '--since', '-s', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--where', '-w', GetoptLong::REQUIRED_ARGUMENT ]
)

cfg=nil
output=nil
debug=false
query=nil

find_params={}
find_params[:conditions] = []

opts.each do |opt,val|
  case opt
    when '--help'
      RDoc::usage
    when '--config'
      cfg = YAML.load_file(val)
    when '--output'
      output=val
    when '--debug'
      debug=true
    when '--since'
      if val == "last-collect"
        find_params = :lastcollect
      elsif val =~ /(\d+)([hdw])/
        val = $1
        case $2
          when 'h'
            val += " HOUR"
          when 'd'
            val += " DAY"
          when 'w'
            val += " WEEK"
        end
        find_params[:conditions].reject! { |v| v =~ /^run_time/ }
        find_params[:conditions] << "run_time >= run_time - #{val}"
      end
      when '--where'
        unless find_params == :lastcollect
          find_params[:conditions] << val
        end
    end
end

if debug then
  ActiveRecord::Base.logger = ActiveSupport::BufferedLogger.new(STDERR, ActiveSupport::BufferedLogger::Severity::DEBUG)
end

if cfg.nil?
  puts "Must specify configuration."
  RDoc::usage
end

if find_params[:conditions].empty?
  find_params = :lastcollect
end

output=:text if output.nil?

case output.to_sym
  when :text
    output=TTT::TextFormatter.new($stdout)
  when :email
    output=TTT::EmailFormatter.new($stdout)
  when :nagios
    output=TTT::NagiosFormatter.new($stdout)
  when nil
    output=TTT::TextFormatter.new($stdout)
end

TTT::Db.open(cfg)


unless find_params == :lastcollect
  output.format(TTT::TableDefinition.find(:all, find_params))
else
  output.format(TTT::TableDefinition.find_table_versions(2))
end
