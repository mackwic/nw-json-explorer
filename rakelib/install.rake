namespace :install do

  task :bundle do
    sh "bundle install"
  end

  task :npm do
    sh "node --version"
    sh "npm install"
  end

  task :bower do
    sh "bower install"
  end

  task :gyps do
    sh "npm install -g node-gyp && npm install -g node-pre-gyp && npm install -g nw-gyp"
  end

  namespace :patches do
    NW_OS   = OS.downcase
    VERSION = "0.8.6"
    NW_ARCH = VERSION != '0.8.6' ?
    'x64' :
      (NW_OS =~ /darwin|win/) ? 'ia32' : 'x64'
    NODE_GYP_OPTS = "--runtime=node --target_arch=#{NW_ARCH} --target=#{VERSION}"

    task :bluetooth => [:npm, :gyps] do
      Dir.chdir "node_modules/bluetooth-serial-port" do
        # temporary fix
        sh "node-gyp clean && node-gyp configure #{NODE_GYP_OPTS} && node-gyp build"
      end
    end

    task :sqlite3 => :npm do
      sh "npm install sqlite3 --runtime=node-webkit --target_arch=#{NW_ARCH} --target=#{VERSION} #{ENV['DEBUG'] || ENV['D'] ? '--verbose' : ''}"
      Dir.chdir "node_modules/sqlite3/lib" do
        unless File.exist? "sqlite3.js"
          raise "File 'sqlite3.js' doesn't exist. Dir content: " + Dir["./*"].to_s
        end

        File.open "sqlite3.js","r+" do |file|
          lines    = file.readlines
          # OK so this is a tricky part.
          # 0) node-gyp can't detect our special flavoured build. so we patch
          #    manually the binary location
          # 1) the application is fully-packaged and can be anywhere. So we need
          #    to look at the sqlite3.so at runtime (it must be an absolute
          #    path)
          # 2) BUT, when running with karma, we are in a tmp directory (platform
          #    specific) which doesn't include the sqlite3.so. So we fallback to
          #    a compile-time known location, as only devs will run karma.

          if (NW_OS == 'win')
            # we need 'win32' here
            lines[2] = "var binding_path = ((-1 != process.cwd().indexOf('/karma-')) ? '#{Dir.pwd}' : (process.cwd() + '/node_modules/sqlite3/lib')) + \"/binding/node-webkit-v#{VERSION}-#{NW_OS}32-#{NW_ARCH}/node_sqlite3.node\";\n"
          else
            lines[2] = "var binding_path = ((-1 != process.cwd().indexOf('/karma-')) ? '#{Dir.pwd}' : (process.cwd() + '/node_modules/sqlite3/lib')) + \"/binding/node-webkit-v#{VERSION}-#{NW_OS}-#{NW_ARCH}/node_sqlite3.node\";\n"
          end
          file.seek 0, IO::SEEK_SET
          file.write lines.join ''
        end
      end
    end
    task :ws do
      sh "cd node_modules/ws && nw-gyp configure --target=0.8.6 && nw-gyp build && cd ../.."
    end
  end
  task :patches => %w{bluetooth sqlite3 ws}.map {|s| "patches:" + s}

  task :all => %w{bundle npm bower patches}
end
