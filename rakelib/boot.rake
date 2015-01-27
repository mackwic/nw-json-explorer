##
# Here are all the constants initialization
#
# Don't put any other logic than constant assignment
#
require 'yaml'
require 'logger'

LOGGER = Logger.new STDOUT
LOGGER.level = Logger::INFO
if (RUBY_PLATFORM =~ /cygwin|mswin|mingw|bccwin|wince|emx/) != nil then
  OS = 'Win'
# only works on ia32 for the time being
  ARCH= 'ia32'
else
  OS = (`uname -o | tr -d [[:space:]]`).sub 'GNU/', '' # remove annoying path killer
  ARCH = `uname -m | tr -d [[:space:]]`
end
ENVIRONMENT = Environment.new (
  ENV['ENVIRONMENT'] || ENV['ENV'] ||
  ('prod' if ENV['PROD'] || ENV['PRODUCTION']) ||
  'dev'
)

CONFIG = FMConfig.new dir: './config', name: 'build'

COPY_TYPES = [:js, :json, :png, :jpeg, :jpg, :yaml, :py, :html, :crt, :svg]

task :dump do |t|
  puts "OS = #{OS}"
  puts "ARCH = #{ARCH}"
  puts "ENVRONMENT = #{ENVIRONMENT}"
  puts "CONFIG = #{CONFIG.inspect}"
end

