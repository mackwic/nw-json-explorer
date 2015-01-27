#########
#
# This is the main Rakefile
#
# It specify the main tasks we will use
#
# Interresting files:
# + rakelib/00_utils: some utility classes
# + rakelib/boot: all the system constants initialization
# + rakelib/rules: how to build a file from another (eg dart->js) from a file
# perspective
# + rakelib/tasks: how to build the project files, from a project perspective
# + config/build.yaml: build configuration
# + config/build.$OS.yaml: specific options related to your OS
# + config/build,,$ENV.yaml: overridding for specific environments
#
#########
require 'rake/clean'

CLEAN.include(Dir['app/**/'].reject do |f|
  f['app/bower_components'] || f['app/node_modules'] || f[%r{^app/$}]
end)
CLEAN.include('app/index.html')
CLOBBER.include('db/*.sqlite3')


# TODO dependre de install
task :default => ['build:all', 'run']

task :run do
  sh "#{CONFIG['node_webkit']['path']} app/ #{if ENV['URL'].nil? then "" else ENV['URL'] end}"
end

desc "Install all the dependencies then apply patches"
task :install => ['install:all']
task :test do
  opts = CONFIG['karma']['options'].map do |o|
    # TODO: merge in FMConfig
    if o.end_with? '!' then
      "-#{o}"
    else
      "--#{o}"
    end
  end
  unless ENV['debug'].nil?
    opts << "--log-level debug"
  end
  opts = opts.join ' '
  sh "NODE_PATH=$PWD/node_modules/ NODEWEBKIT_BIN=$PWD/#{CONFIG['node_webkit']['path']} ./node_modules/karma/bin/karma start test/karma.conf.js #{opts}"
end

