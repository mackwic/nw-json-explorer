namespace :test do

  task :unit => 'unit:all'

  namespace :unit do

    MOCHA_GLOBALS = [ 'jQuery', 'angular']
    MOCHA_DEPENDENCIES = [ ]

    MOCHA_OPTS = [
      "--ui bdd",     # use the Behavior Driven interface
      "--slow 15",    # a test is slow if it last longuer than 15ms
      "--timeout 50", # tests timeout at 50ms
      "--colors",
      "--globals #{MOCHA_GLOBALS.join ","}",
      "--reporter spec",
      "--check-leaks",
      "--compilers coffee:coffee-script/register"
    ]
    MOCHA_BIN = "node_modules/.bin/mocha"

    task :all do
      sh "#{MOCHA_BIN} #{MOCHA_OPTS.join ' '} --recursive test/spec"
    end

    task :f, [:file] do |t, args|
      file = (args.file.include? "test/spec") ? args.file : "test/spec/#{args.file}"
      file += ".coffee" unless file.include? "coffee"
      sh "#{MOCHA_BIN} #{MOCHA_OPTS.join ' '} #{file}"
    end
  end


end
