# == Synopsis
#
# ttt-collect: Run a table tracking collection
#
# == Usage
#
# ttt-collect [--help] --config config.yml --dsn servers.yml
#
# -h, --help:
#    This help
# --config file, -c file:
#    Path to ttt config file.
# --debug:
#    Make the tool VERY noisy.
# --dsn file, -d file:
#    Path to PalominoDB dsn.yml
#
require 'rubygems'
require 'yaml'
require 'getoptlong'
require 'rdoc/usage'
require 'open-uri'
require 'pp'

require 'pdb/dsn'
require 'ttt/db'
require 'ttt/collector'

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
  [ '--config', '-c', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--dsn', '-d', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--debug', GetoptLong::NO_ARGUMENT ]
)

dsn=nil
cfg=nil
debug=false

opts.each do |opt, val|
  case opt
    when '--help'
      RDoc::usage
    when '--config'
      cfg = YAML.load_file(val)
    when '--dsn'
      dsn = Pdb::DSN.new(val)
      dsn.validate
    when '--debug'
      debug=true
  end
end

if cfg.nil?
  puts "Must specify configuration."
  RDoc::usage
end
if dsn.nil?
  puts "Must specify dsn."
  RDoc::usage
end

if debug then
  ActiveRecord::Base.logger = ActiveSupport::BufferedLogger.new(STDOUT, ActiveSupport::BufferedLogger::Severity::DEBUG)
else
  ActiveRecord::Base.logger = ActiveSupport::BufferedLogger.new(STDOUT, ActiveSupport::BufferedLogger::Severity::INFO)
end

TTT::Db.open(cfg)
# Creates the database, if it doesn't exist,
# and will upgrade it too!
TTT::Db.migrate

TTT::Collector.verbose = false
TTT::Collector.load_all

TTT::TableDefinition.transaction do
  dsn.get_all_hosts.each do |host|
    if !dsn.host_active? host
      next
    end
    TTT::Collector.say "[host] #{host}"
    TTT::Collector.each do |coller|
      coller.collect(host,cfg)
    end
  end
end
