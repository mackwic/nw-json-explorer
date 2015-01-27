
namespace :build do

  desc 'Build all the coffee files, slim files and scss files'
  task :all => [
    "coffee:all", "js:all", "json:all", "yaml:all", "svg:all",
    "png:all", "jpg:all", "jpeg:all", "py:all", "html:all",
    "crt:all", "scss:all", "slim:all", "html"
  ]

  namespace :coffee do
    COFFEE_OPTIONS = {
      glob: 'src/**/*.coffee',
      from_dir: 'src/', to_dir: 'app/',
      from_type: :coffee, to_type: :js,
      abbrev: {
        ctrl: 'common/controllers/',
        dirs: 'directives/',
        srv: 'common/services/'
      },
      lint: {
        bin: './node_modules/.bin/coffeelint'
      }
    }

    declare_transform_tasks(COFFEE_OPTIONS)
  end

  COPY_TYPES.each do |type|
    namespace type do
      options = {
        glob: "src/**/*.#{type.to_s}",
        from_dir: 'src/', to_dir: 'app/',
        from_type: type, to_type: type
      }
      declare_transform_tasks options
    end
  end

  namespace :slim do
    SLIM_OPTIONS = {
      glob: 'src/**/*.slim',
      from_dir: 'src/', to_dir: 'app/',
      from_type: :slim, to_type: :html,
      exclude: ['src/index.slim', 'src/skel.slim'],
      abbrev: {
        lyt: 'layout/',
        dirs: 'directives/'
      }
    }

    declare_transform_tasks(SLIM_OPTIONS)
  end

  namespace :scss do
    SCSS_OPTIONS = {
      glob: 'src/**/*.scss',
      from_dir: 'src/scss/', to_dir: 'app/css/',
      from_type: :scss, to_type: :css,
      lint: {
        bin: 'scss-lint',
      }
    }

    declare_transform_tasks(SCSS_OPTIONS)
  end

  def add_file(js, css, root, f)
    file = root + '/' + f
    if f.end_with? '.js'
      js << file
    elsif f.end_with? '.css'
      css << file
    end
  end

  desc 'Build app/index.html from src/skel.slim injecting scripts'
  task :html => 'build:inject_userinfo' do
    require 'json'

    css_vendor = []
    css_src = Dir['src/scss/**/*.scss'].map! {|f| f.sub!('src/', '').gsub! 'scss', 'css'}

    # we need to put the common directory before the others
    special_sort = Proc.new do |a,b|
      a_common = a.include? 'src/common'
      b_common = b.include? 'src/common'
      case [a_common, b_common]
      when [true, true], [false, false] then a <=> b
      when [true, false] then -1  # b follow a
      when [false, true] then 1 # a follow b
      end
    end

    js_vendor = []
    js_src = Rake::FileList.new 'src/**/*.coffee'
    js_src.exclude 'src/workers/**/*'
    js_src.to_a.sort!(&special_sort).map! {|f| f.sub!('src/', '').sub! 'coffee', 'js'}

    ng_tpl = Rake::FileList.new 'app/*/*.html'

    CONFIG['vendor'].each do |dep|
      LOADER.load dep do |pkg_root, file|
        add_file js_vendor, css_vendor, pkg_root, file
      end
    end

    css_link = Proc.new do |f|
      "    link rel=\"stylesheet\" href=\"#{f}\""
    end
    js_link = Proc.new do |f|
      "    script type=\"text/javascript\" src=\"#{f}\""
    end
    tpls_link = Proc.new do |file|
      id = file.sub 'app/', ''
      head = "    script type=\"text/ng-template\" id=\"#{id}\""
      padd = "      | "
      content = File.readlines(file).map!{|l| padd + l}.join ""
      head + "\n" + content
    end

    js_vendor = js_vendor.map!(&js_link).join "\n"
    js_src = js_src.map!(&js_link).join "\n"
    css_vendor = css_vendor.map!(&css_link).join "\n"
    css_src = css_src.map!(&css_link).join "\n"
    ng_tpl  = ng_tpl.map!(&tpls_link).join "\n"

    skel = File.read('src/skel.slim')
    skel.sub! '@_ENVIRONMENT_@', ENVIRONMENT.to_s
    skel.sub! '/ @_CSS_VENDOR_@', css_vendor
    skel.sub! '/ @_JS_VENDOR_@', js_vendor
    skel.sub! '/ @_CSS_SRC_@', css_src
    skel.sub! '/ @_CONFIG_@', CONFIG.to_slim
    skel.sub! '/ @_JS_SRC_@', js_src
    skel.sub! '/ @_NG_TEMPLATES_@', ng_tpl

    File.write('src/index.slim', skel)
    compile_from_slim_to_html 'src/index.slim', 'app/index.html'

    sh "cp -r ./app/bower_components/ui-bootstrap/template ./app/template" unless File.exists? "app/template"
    puts "Build index.html OK"
  end

end
