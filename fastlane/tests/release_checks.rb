# frozen_string_literal: true

require 'open3'
require 'plist'
require 'tempfile'

# Exercise the actual Fastfile against disposable Git repositories. Apple and
# GitHub calls are replaced; no credentials, signing, or network are used.
class MathReduceReleaseChecks
  FASTFILE = File.expand_path('../Fastfile', __dir__)
  # A disposable key generated locally; never used with Apple or any other service.
  FAKE_PRIVATE_KEY = OpenSSL::PKey::EC.generate('prime256v1').private_to_pem.freeze

  def self.run
    checks = instance_methods(false).grep(/^check_/).sort
    checks.each do |check|
      output = Tempfile.new('math-reduce-release-check-log-')
      original_stdout, original_stderr = $stdout, $stderr
      original_ui = FastlaneCore::UI.ui_object
      original_actions = Fastlane::Actions.executed_actions.dup
      begin
        $stdout = $stderr = output
        FastlaneCore::UI.ui_object = FastlaneCore::Shell.new
        Dir.mktmpdir('math-reduce-release-test-') { |root| new(root).with_fixture { |fixture| fixture.public_send(check) } }
      rescue StandardError
        output.rewind
        original_stderr.puts(output.read)
        raise
      ensure
        $stdout, $stderr = original_stdout, original_stderr
        FastlaneCore::UI.ui_object = original_ui
        Fastlane::Actions.executed_actions.replace(original_actions)
        output.close!
      end
      FastlaneCore::UI.success(check.to_s.sub('check_', '').tr('_', ' '))
    end
    FastlaneCore::UI.success("#{checks.length} offline release checks passed.")
  end

  def initialize(root)
    @root = root
    @commands = []
    @creates = 0
    @package_count = 0
  end

  def with_fixture
    environment = ENV.to_h
    lane_context = Fastlane::Actions.lane_context.dup
    ENV['GITHUB_REPOSITORY'] = 'example/math-reduce'
    ENV['GITHUB_TOKEN'] = 'offline-test-token'
    ENV['SIGNING_IDENTITY'] = 'Developer ID Application: Offline Test'
    ENV['NOTARYTOOL_PROFILE'] = 'offline-test-profile'
    ENV.delete('GH_TOKEN')
    FileUtils.mkdir_p(["#{@root}/fastlane", "#{@root}/Resources"])
    @info = { 'CFBundleShortVersionString' => '2.0.0', 'CFBundleVersion' => '2.0.0',
              'NSServices' => [{ 'NSMessage' => 'reduceMath' }] }
    File.write("#{@root}/Resources/Info.plist", Plist::Emit.dump(@info))
    File.write("#{@root}/codemeta.json", JSON.generate('version' => '0.1.0'))
    File.write("#{@root}/readme.md", 'Offline test fixture')
    File.write("#{@root}/.gitignore", "dist/\n")
    git('init', '-b', 'main')
    git('config', 'user.name', 'Release test')
    git('config', 'user.email', 'release-test@example.invalid')
    git('config', 'commit.gpgsign', 'false')
    git('config', 'tag.gpgsign', 'false')
    git('config', 'core.hooksPath', '.git/no-hooks')
    git('add', '.')
    git('commit', '-m', 'Initial fixture')
    git('remote', 'add', 'origin', 'https://github.com/example/math-reduce.git')
    git('update-ref', 'refs/remotes/origin/main', 'HEAD')
    Dir.chdir(@root) do
      @fastfile = Fastlane::FastFile.new(FASTFILE)
      @project = MathReduceProject.new(@root, @fastfile)
      @fastfile.instance_variable_set(:@project, @project)
      fixture = self
      @project.define_singleton_method(:run) { |*args, **options| fixture.command(*args, **options) }
      @project.define_singleton_method(:check_signing) {}
      @project.define_singleton_method(:homebrew) { fixture.homebrew }
      @project.define_singleton_method(:service_directories) { [path('UserServices'), path('SystemServices')] }
      @fastfile.define_singleton_method(:test) {}
      @fastfile.define_singleton_method(:package) { fixture.package }
      @fastfile.define_singleton_method(:github_api) { |**options| fixture.github(**options) }
      @fastfile.define_singleton_method(:set_github_release) { |**options| fixture.create_release(**options) }
      yield self
    end
  ensure
    ENV.replace(environment)
    Fastlane::Actions.lane_context.replace(lane_context)
  end

  def git(*args)
    output, status = Open3.capture2e('git', *args, chdir: @root)
    raise output unless status.success?
    output.strip
  end

  def command(*args, **_options)
    @commands << args
    case args.take(2)
    when %w[git fetch], %w[git push]
      ''
    when %w[gh release]
      case args[2]
      when 'view'
        expect(args[3] == @remote.fetch('tag_name'), 'Verified the wrong release')
        JSON.generate('isDraft' => @remote.fetch('draft'), 'isPrerelease' => false, 'assets' => @remote.fetch('assets'))
      when 'download'
        raise 'Download failed' if @fail_download
        File.binwrite(File.join(args.last, @project.asset_name), @download_bytes || 'signed release dmg')
        ''
      when 'upload'
        raise 'Upload failed' if @fail_upload
        @remote['assets'] = args[4..5].map { |file| { 'name' => File.basename(file) } }
        ''
      else
        raise "Unexpected command: #{args.inspect}"
      end
    when %w[brew list]
      expect(args == %w[brew list --cask -1], 'Uninstall did not query installed casks')
      @brew_installed ? "math-reduce\nother-cask" : 'other-cask'
    when %w[brew uninstall]
      expect(args == %w[brew uninstall --cask math-reduce], 'Uninstall targeted the wrong cask')
      raise 'Homebrew uninstall failed' if @fail_brew_uninstall
      FileUtils.remove_entry(@brew_bundle) if @brew_bundle
      @brew_installed = false
      ''
    when %w[sudo /bin/rm]
      expect(args.take(4) == %w[sudo /bin/rm -R --] && args.last.start_with?(@root + '/'), 'Unsafe privileged removal')
      File.chmod(0o755, File.dirname(args.last))
      FileUtils.remove_entry(args.last)
      ''
    when [MathReduceProject::LSREGISTER, '-dump']
      @registrations || ''
    when [MathReduceProject::LSREGISTER, '-u']
      raise 'Unregister failed' if @fail_unregister
      (@unregistered ||= []) << args.fetch(2)
      ''
    when [MathReduceProject::PBS, '-update']
      @refreshed_services = true
      ''
    when %w[ditto stub.service]
      FileUtils.mkdir_p(args.last)
      ''
    when %w[hdiutil create]
      File.binwrite(args.last, 'signed release dmg')
      ''
    when %w[codesign --force], %w[codesign --verify], %w[spctl --assess], %w[xcrun stapler]
      ''
    when %w[op inject]
      expect(args.fetch(args.index('--file-mode') + 1) == '0600', 'Generated .env permissions were not specified')
      File.open(@project.path('.env'), File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
        file.write("NOTARYTOOL_PROFILE=new-profile\nAPP_STORE_DEV_KEY_ID=TESTKEY123\nAPP_STORE_DEV_KEY_NAME=\"Test key\"\nAPP_STORE_DEV_KEY_ISSUER_ID=test-issuer\n")
      end
      ''
    when %w[op read]
      expect(args[2] == 'op://Personal/Apple/APP_STORE_DEV_KEY', 'Read the wrong private-key field')
      expect(args.fetch(args.index('--file-mode') + 1) == '0600', 'Private-key permissions were not specified')
      @temporary_key = args.fetch(args.index('--out-file') + 1)
      File.open(@temporary_key, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(@key_contents || FAKE_PRIVATE_KEY) }
      raise 'Key retrieval failed' if @fail_key_read
      ''
    when %w[xcrun notarytool]
      if args[2] == 'store-credentials'
        expect(args[3] == 'new-profile', 'Init used the stale profile loaded before .env was regenerated')
        expect(args.fetch(args.index('--key-id') + 1) == 'TESTKEY123', 'Wrong Key ID')
        expect(args.fetch(args.index('--issuer') + 1) == 'test-issuer', 'Wrong Issuer ID')
        key_file = args.fetch(args.index('--key') + 1)
        expect(File.binread(key_file) == FAKE_PRIVATE_KEY, 'The multiline key was not preserved')
        expect(File.stat(key_file).mode & 0o777 == 0o600, 'The key file was not private')
        expect(File.stat(File.dirname(key_file)).mode & 0o777 == 0o700, 'The temporary directory was not private')
        raise 'Credentials rejected' if @fail_credentials
        return ''
      end
      JSON.generate('status' => @notary_status || 'Accepted', 'id' => 'offline-test')
    else
      raise "Unexpected external command: #{args.inspect}" unless args.first == 'git'
      git(*args.drop(1))
    end
  end

  def github(**options)
    path = options.fetch(:path)
    if path == 'repos/example/math-reduce'
      return { status: 200, json: { 'default_branch' => 'main' } }
    end
    if options[:http_method] == 'PATCH'
      expect(@remote['assets'].length == 2, 'A draft was published before both assets were uploaded')
      @remote['draft'] = false
    elsif !@remote
      options.fetch(:error_handlers).fetch(404).call(status: 404)
      return { status: 404, json: {} }
    end
    { status: 200, json: @remote }
  end

  def create_release(**options)
    @creates += 1
    expect(options[:tag_name] == "v#{@project.version}" && options[:is_draft], 'Wrong release version or visibility')
    @remote = { 'id' => 123, 'tag_name' => options[:tag_name], 'draft' => true, 'prerelease' => false, 'assets' => [] }
    raise 'Upload failed' if @fail_upload
    @remote['assets'] = options.fetch(:upload_assets).map { |file| { 'name' => File.basename(file) } }
    @remote
  end

  def package
    @package_count += 1
    raise 'Notarization failed' if @fail_package
    FileUtils.mkdir_p(@project.path('dist'))
    file = @project.path("dist/#{@project.asset_name}")
    File.binwrite(file, 'signed release dmg')
    file
  end

  def homebrew
    'brew' if @brew_available
  end

  def service_fixture(directory, name, identifier: 'com.kitschpatrol.MathReduce', binary: false)
    bundle = @project.path("#{directory}/#{name}")
    FileUtils.mkdir_p(File.join(bundle, 'Contents'))
    info = CFPropertyList::List.new
    info.value = CFPropertyList.guess('CFBundleIdentifier' => identifier)
    info.save(File.join(bundle, 'Contents/Info.plist'), binary ? CFPropertyList::List::FORMAT_BINARY : CFPropertyList::List::FORMAT_XML)
    bundle
  end

  def execute(lane, **options)
    @fastfile.runner.execute(lane, :mac, options)
  end

  def expect(value, message)
    raise message unless value
  end

  def expect_failure(message)
    begin
      yield
    rescue StandardError => error
      raise unless error.message.include?(message)
      return
    end
    raise "Expected failure containing #{message.inspect}"
  end

  def check_version_validation
    { 'current' => '2.0.0', 'patch' => '2.0.1', 'minor' => '2.1.0', 'major' => '3.0.0', '4.5.6' => '4.5.6' }.each do |bump, expected|
      expect(@project.next_version(bump) == expected, "Wrong version for #{bump}")
    end
    ['1.0.0', '2.0.0'].each { |value| expect_failure('newer') { @project.next_version(value) } }
    [nil, 2, '02.0.0', '2.1', '3.0.0-beta.1', "3.0.0\n", '$(touch oops)'].each do |value|
      expect_failure('Expected a stable version') { @project.validate_version(value) }
    end
  end

  def check_successful_release
    execute(:release, bump: 'minor')
    info = Plist.parse_xml(@project.path('Resources/Info.plist'))
    expect(info == @info.merge('CFBundleShortVersionString' => '2.1.0', 'CFBundleVersion' => '2.1.0'), 'Plist metadata was lost')
    expect(JSON.parse(File.read(@project.path('codemeta.json')))['version'] == '2.1.0', 'Codemeta was not synchronized')
    expect(git('rev-parse', 'v2.1.0^{commit}') == git('rev-parse', 'HEAD'), 'Tag points to the wrong commit')
    expect(git('show', '--format=', '--name-only', 'HEAD').lines.map(&:strip).sort == MathReduceProject::VERSION_FILES.sort, 'Wrong files committed')
    expect(@remote['tag_name'] == 'v2.1.0' && !@remote['draft'] && @project.state['complete'], 'GitHub publication was not completed')
  end

  def check_current_release_tags_existing_commit_and_resumes
    File.write(@project.path('codemeta.json'), JSON.generate('version' => '2.0.0'))
    git('add', 'codemeta.json')
    git('commit', '-m', 'Prepare current version')
    parent = git('rev-parse', 'HEAD')
    git('update-ref', 'refs/remotes/origin/main', parent)
    originals = MathReduceProject::VERSION_FILES.to_h { |file| [file, File.binread(@project.path(file))] }
    @fail_upload = true
    expect_failure('Upload failed') { execute(:release, bump: 'current') }
    expect(git('rev-parse', 'v2.0.0^{commit}') == parent, 'Current release created an extra commit')
    originals.each { |file, bytes| expect(File.binread(@project.path(file)) == bytes, "Current release rewrote #{file}") }
    @fail_upload = false
    execute(:resume)
    expect(git('rev-parse', 'HEAD') == parent && @package_count == 1 && @creates == 1, 'Resume rebuilt, recommitted, or created another release')
    expect(@remote['tag_name'] == 'v2.0.0' && !@remote['draft'] && @project.state['complete'], 'Current version was not published')
  end

  def check_current_release_synchronizes_stale_metadata
    original = File.binread(@project.path('Resources/Info.plist'))
    execute(:release, bump: 'current')
    expect(File.binread(@project.path('Resources/Info.plist')) == original, 'Current release changed the app version')
    expect(JSON.parse(File.read(@project.path('codemeta.json')))['version'] == '2.0.0', 'Current release did not synchronize codemeta')
    expect(git('show', '--format=', '--name-only', 'HEAD') == 'codemeta.json', 'Current release committed unexpected files')
    expect(@remote['tag_name'] == 'v2.0.0' && !@remote['draft'] && @project.state['complete'], 'Current release did not finish')
  end

  def check_current_release_rejects_existing_tag
    git('tag', 'v2.0.0')
    expect_failure('Tag v2.0.0 already exists') { execute(:release, bump: 'current') }
    expect(@package_count.zero? && @project.state.nil?, 'Existing tag allowed another release')
  end

  def check_build_failure_restores_metadata
    originals = MathReduceProject::VERSION_FILES.to_h { |file| [file, File.binread(@project.path(file))] }
    @fail_package = true
    expect_failure('Notarization failed') { execute(:release) }
    originals.each { |file, bytes| expect(File.binread(@project.path(file)) == bytes, "#{file} was not restored exactly") }
    expect(git('rev-list', '--count', 'HEAD') == '1' && @project.state.nil?, 'Failed build created a release commit or receipt')
  end

  def check_upload_failure_resumes_existing_draft
    @fail_upload = true
    expect_failure('Upload failed') { execute(:release) }
    expect(@remote['draft'], 'Failed upload published the release')
    @fail_upload = false
    execute(:resume)
    expect(@creates == 1 && @package_count == 1, 'Resume created another release or rebuilt the asset')
    expect(git('rev-list', '--count', 'HEAD') == '2' && @project.version == '2.0.1', 'Resume bumped or committed again')
    expect(@project.state['complete'], 'Resume did not finish')
  end

  def check_verification_failure_keeps_published_assets
    @fail_download = true
    expect_failure('Download failed') { execute(:release) }
    expect(!@remote['draft'], 'GitHub release should already be published')
    expect(!@project.state['complete'], 'Unverified release was marked complete')
    @fail_download = false
    @commands.clear
    execute(:resume)
    expect(@creates == 1 && @commands.none? { |command| command.take(3) == %w[gh release upload] }, 'Resume replaced published assets')
    expect(@remote['tag_name'] == 'v2.0.1' && @project.state['complete'], 'GitHub verification retry did not finish')
  end

  def check_tampered_asset_blocks_resume
    @fail_upload = true
    expect_failure('Upload failed') { execute(:release) }
    File.write(@project.path("dist/#{@project.asset_name}"), 'changed')
    @commands.clear
    expect_failure('artifact changed') { execute(:resume) }
    expect(@commands.none? { |command| command.take(2) == %w[git push] }, 'Changed artifact reached publication')
  end

  def check_packaging_preserves_an_interrupted_release
    @fail_upload = true
    expect_failure('Upload failed') { execute(:release) }
    artifact = @project.path("dist/#{@project.asset_name}")
    original = File.binread(artifact)
    @commands.clear
    expect_failure('Run just resume before packaging again') { @project.package }
    expect(@commands.empty? && File.binread(artifact) == original, 'Packaging overwrote the recoverable release')
  end

  def check_changed_plist_blocks_resume
    @fail_upload = true
    expect_failure('Upload failed') { execute(:release) }
    File.open(@project.path('Resources/Info.plist'), 'a') { |file| file.puts('<!-- changed after signing -->') }
    expect_failure('Info.plist changed') { execute(:resume) }
  end

  def check_unrelated_commit_changes_block_resume
    @fastfile.define_singleton_method(:resume) {}
    execute(:release)
    File.write(@project.path('readme.md'), 'Changed after packaging')
    git('add', '.')
    git('commit', '-m', 'Release: v2.0.1')
    @commands.clear
    expect_failure('HEAD changed') { execute(:resume) }
    expect(@commands.none? { |command| command.take(2) == %w[git push] }, 'An altered source commit was pushed')
  end

  def check_wrong_download_blocks_completion
    @download_bytes = 'wrong uploaded bytes'
    expect_failure('differs from the signed local artifact') { execute(:release) }
    expect(!@project.state['complete'], 'An unverified asset was marked complete')
  end

  def check_unknown_receipt_is_rejected
    @project.save_state('schema' => 999)
    expect_failure('Unsupported release state') { execute(:resume) }
    expect(@commands.empty?, 'An unknown receipt caused external calls')
  end

  def check_init_imports_key_and_removes_temporary_file
    execute(:setup)
    expect(!File.exist?(File.dirname(@temporary_key)), 'Init left the temporary key directory behind')
    env_file = @project.path('.env')
    expect(!File.read(env_file).include?('PRIVATE KEY'), 'The private key was written to .env')
    expect(File.stat(env_file).mode & 0o777 == 0o600, 'The generated .env was not private')
  end

  def check_init_cleans_up_after_rejected_credentials
    @fail_credentials = true
    expect_failure('Credentials rejected') { execute(:setup) }
    expect(!File.exist?(File.dirname(@temporary_key)), 'Rejected credentials left the private key on disk')
  end

  def check_init_normalizes_password_field_formatting
    [FAKE_PRIVATE_KEY.tr("\n", ' '), FAKE_PRIVATE_KEY.delete("\n"),
     FAKE_PRIVATE_KEY.gsub("\n", '\\n'), FAKE_PRIVATE_KEY.gsub("\n", '\\r\\n'),
     FAKE_PRIVATE_KEY.gsub("\n", "\r\n")].each do |contents|
      @key_contents = contents
      execute(:setup)
      expect(!File.exist?(File.dirname(@temporary_key)), 'Normalized key was left on disk')
    end
  end

  def check_init_rejects_invalid_keys_before_import
    ['not a key', FAKE_PRIVATE_KEY.sub('-----END PRIVATE KEY-----', ''),
     "-----BEGIN PRIVATE KEY-----\ninvalid-payload\n-----END PRIVATE KEY-----\n",
     "-----BEGIN PRIVATE KEY-----\nYWJj\n-----END PRIVATE KEY-----\n",
     OpenSSL::PKey::EC.generate('secp384r1').private_to_pem,
     OpenSSL::PKey::EC.generate('prime256v1').public_to_pem].each do |contents|
      @key_contents = contents
      expect_failure('APP_STORE_DEV_KEY is not a valid App Store Connect private key') { execute(:setup) }
      expect(!File.exist?(File.dirname(@temporary_key)), 'Invalid key was left on disk')
      expect(@commands.none? { |command| command.take(3) == %w[xcrun notarytool store-credentials] }, 'Invalid key reached Keychain import')
    end
  end

  def check_init_cleans_up_after_failed_key_retrieval
    @fail_key_read = true
    expect_failure('Key retrieval failed') { execute(:setup) }
    expect(!File.exist?(File.dirname(@temporary_key)), 'Failed retrieval left a partial key on disk')
    expect(@commands.none? { |command| command.take(3) == %w[xcrun notarytool store-credentials] }, 'Incomplete key reached Keychain import')
  end

  def check_uninstall_removes_copies_and_preserves_other_services
    user = service_fixture('UserServices', 'MathReduce.service')
    renamed = service_fixture('SystemServices', 'Math Reduce old copy.service', binary: true)
    unrelated = service_fixture('SystemServices', 'MathReduce.service', identifier: 'example.other-service')
    malformed = @project.path('UserServices/Broken.service/Contents')
    FileUtils.mkdir_p(malformed)
    File.write(File.join(malformed, 'Info.plist'), 'not a plist')
    execute(:uninstall)
    expect(!File.exist?(user) && !File.exist?(renamed), 'Uninstall left an installed copy')
    expect(File.directory?(unrelated) && File.directory?(malformed), 'Uninstall removed another service')
    expect(@refreshed_services, 'Uninstall did not refresh Services')
    expect(@commands.none? { |command| command.first == 'sudo' }, 'Writable services required sudo')
  end

  def check_uninstall_preserves_symlink_targets
    target = service_fixture('Build', 'MathReduce.service')
    FileUtils.mkdir_p(@project.path('UserServices'))
    link = @project.path('UserServices/Renamed.service')
    dangling = @project.path('UserServices/MathReduce.service')
    File.symlink(target, link)
    File.symlink(@project.path('missing.service'), dangling)
    execute(:uninstall)
    expect(!File.symlink?(link) && !File.symlink?(dangling), 'Uninstall left a service symlink')
    expect(File.file?(File.join(target, 'Contents/Info.plist')), 'Uninstall followed a symlink into a build')
  end

  def check_uninstall_unregisters_builds_and_mounted_copies
    installed = service_fixture('UserServices', 'MathReduce.service')
    build = service_fixture('dist', 'MathReduce.service')
    mounted = service_fixture('Volumes/Math Reduce', 'MathReduce.service', binary: true)
    old = service_fixture('Temporary Build', 'Renamed.service')
    unrelated = service_fixture('Other', 'MathReduce.service', identifier: 'example.other-service')
    missing = @project.path('Missing/MathReduce.service')
    @registrations = [installed, build, mounted, old, unrelated, missing, build].map do |bundle|
      # Include a stale record whose on-disk bundle now belongs to another app.
      "#{'-' * 80}\nbundle id: Math Reduce (0x123)\npath: #{bundle} (0x456)\nidentifier: com.kitschpatrol.MathReduce\n"
    end.join
    @registrations += "#{'-' * 80}\npath: #{unrelated} (0x789)\nidentifier: example.other-service\n"
    execute(:uninstall)
    expect(@unregistered == [installed, build, mounted, old], 'Uninstall missed a provider or unregistered an unrelated bundle')
    expect(!File.exist?(installed), 'Uninstall left the installed copy')
    [build, mounted, old, unrelated].each { |bundle| expect(File.directory?(bundle), 'Uninstall deleted a non-installed bundle') }
    refresh_index = @commands.index([MathReduceProject::PBS, '-update'])
    expect(refresh_index && @commands.each_index.all? { |i| @commands[i].take(2) != [MathReduceProject::LSREGISTER, '-u'] || i < refresh_index }, 'Services refreshed before unregistering providers')
  end

  def check_uninstall_stops_when_unregistering_fails
    build = service_fixture('dist', 'MathReduce.service')
    @registrations = "#{'-' * 80}\npath: #{build} (0x123)\nidentifier: com.kitschpatrol.MathReduce\n"
    @fail_unregister = true
    expect_failure('Unregister failed') { execute(:uninstall) }
    expect(!@refreshed_services && File.directory?(build), 'Failed unregister claimed success or removed the build')
  end

  def check_uninstall_uses_homebrew_and_allows_repeated_runs
    @brew_available = @brew_installed = true
    @brew_bundle = service_fixture('UserServices', 'MathReduce.service')
    manual = service_fixture('SystemServices', 'Manual.service')
    execute(:uninstall)
    expect(!File.exist?(@brew_bundle) && !File.exist?(manual), 'Uninstall left a cask or manual installation')
    execute(:uninstall)
    expect(@commands.count { |command| command.take(2) == %w[brew uninstall] } == 1, 'Uninstall retried an absent cask')
    expect(@refreshed_services, 'Uninstall did not refresh Services')
  end

  def check_uninstall_stops_if_homebrew_fails
    @brew_available = @brew_installed = @fail_brew_uninstall = true
    @brew_bundle = service_fixture('UserServices', 'MathReduce.service')
    expect_failure('Homebrew uninstall failed') { execute(:uninstall) }
    expect(File.exist?(@brew_bundle), 'Failed Homebrew uninstall fell back to deleting its files')
    expect(!@refreshed_services, 'Failed uninstall reported completion')
  end

  def check_uninstall_elevates_only_protected_deletion
    bundle = service_fixture('SystemServices', 'Protected copy.service')
    parent = File.dirname(bundle)
    File.chmod(0o555, parent)
    execute(:uninstall)
    expect(@commands.include?(['sudo', '/bin/rm', '-R', '--', bundle]), 'Protected deletion did not use sudo')
    expect(!File.exist?(bundle) && @refreshed_services, 'Protected installation was not removed and refreshed')
  ensure
    File.chmod(0o755, parent) if parent && File.directory?(parent)
  end

  def check_notarization_failure_stops_packaging
    @project.define_singleton_method(:build) { |signed:| raise 'Expected signing' unless signed; 'stub.service' }
    FileUtils.mkdir_p(@project.path('dist'))
    @notary_status = 'Invalid'
    expect_failure('Notarization was not accepted') { @project.package }
    expect(@commands.none? { |command| command.take(2) == %w[xcrun stapler] }, 'Rejected artifact was stapled')
    expect(!File.exist?(@project.path("dist/#{@project.asset_name}.sha256")), 'Rejected artifact received a release checksum')
  end

  def check_packaging_staples_the_dmg
    @project.define_singleton_method(:build) { |signed:| raise 'Expected signing' unless signed; 'stub.service' }
    FileUtils.mkdir_p(@project.path('dist'))
    dmg = @project.package
    expect(@commands.include?(['xcrun', 'stapler', 'staple', dmg]), 'The DMG was not stapled')
    expect(@commands.include?(['xcrun', 'stapler', 'validate', dmg]), 'The ticket was not validated')
    expect(@commands.any? { |command| command.first == 'spctl' && command.last == dmg }, 'Gatekeeper did not check the DMG')
    expect(File.read(dmg + '.sha256').start_with?(@project.digest(dmg)), 'The checksum differs from the packaged artifact')
  end
end
