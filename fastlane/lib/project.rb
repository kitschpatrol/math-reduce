# frozen_string_literal: true

require 'cfpropertylist'
require 'digest'
require 'fileutils'
require 'json'
require 'openssl'
require 'tmpdir'

# The parts specific to a SwiftPM-built .service bundle. Fastfile owns the release flow.
class MathReduceProject
  VERSION_FILES = ['Resources/Info.plist', 'codemeta.json'].freeze
  attr_reader :root

  def initialize(root, fastfile)
    @root = root
    @fastfile = fastfile
  end

  def path(relative)
    File.join(root, relative)
  end

  def run(*args, **options)
    Dir.chdir(root) { Fastlane::Actions.sh(*args.map(&:to_s), **options).strip }
  end

  def normalize_notary_key(file)
    # Password fields can flatten PEM line breaks or store them as literal \n.
    value = File.binread(file).gsub('\\r\\n', "\n").gsub('\\n', "\n").strip
    match = value.match(/\A-----BEGIN PRIVATE KEY-----([A-Za-z0-9+\/=\s]+)-----END PRIVATE KEY-----\z/)
    message = 'APP_STORE_DEV_KEY is not a valid App Store Connect private key. ' \
              'Copy the complete original .p8 contents, including BEGIN/END PRIVATE KEY, into the 1Password field.'
    raise message unless match

    body = match[1].gsub(/\s/, '').scan(/.{1,64}/).join("\n")
    pem = "-----BEGIN PRIVATE KEY-----\n#{body}\n-----END PRIVATE KEY-----\n"
    begin
      key = OpenSSL::PKey.read(pem)
    rescue OpenSSL::OpenSSLError, ArgumentError
      # Keep parser diagnostics and private-key contents out of fastlane's output.
      raise message, cause: nil
    end
    raise message unless key.is_a?(OpenSSL::PKey::EC) && key.private? && key.group.curve_name == 'prime256v1'

    File.open(file, 'wb', 0o600) do |output|
      output.chmod(0o600)
      output.write(pem)
    end
  end

  def version
    value = @fastfile.get_info_plist_value(path: path(VERSION_FILES.first), key: 'CFBundleShortVersionString')
    validate_version(value)
  end

  def validate_version(value)
    unless value.is_a?(String) && value.match?(/\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/)
      raise "Expected a stable version X.Y.Z, got #{value.inspect}."
    end
    value
  end

  def next_version(bump)
    current = version
    return current if bump == 'current'

    parts = current.split('.').map(&:to_i)
    index = %w[major minor patch].index(bump)
    if index
      parts[index] += 1
      ((index + 1)..2).each { |i| parts[i] = 0 }
      bump = parts.join('.')
    end
    validate_version(bump)
    raise 'The release version must be newer than Resources/Info.plist.' unless Gem::Version.new(bump) > Gem::Version.new(current)
    bump
  end

  def repository
    value = ENV.fetch('GITHUB_REPOSITORY', 'kitschpatrol/math-reduce')
    raise 'GITHUB_REPOSITORY must be owner/repository.' unless value.match?(%r{\A[\w.-]+/[\w.-]+\z})
    value
  end

  def token
    @token ||= ENV['GH_TOKEN'] || ENV['GITHUB_TOKEN'] || run('gh', 'auth', 'token', log: false)
  end

  def check_origin
    remote = run('git', 'remote', 'get-url', 'origin')
    allowed = ["https://github.com/#{repository}", "https://github.com/#{repository}.git", "git@github.com:#{repository}.git"]
    raise 'origin does not match GITHUB_REPOSITORY.' unless allowed.include?(remote)
  end

  def asset_name(value = version)
    "MathReduce-#{validate_version(value)}-universal.dmg"
  end

  def digest(file)
    Digest::SHA256.file(file).hexdigest
  end

  def check_signing
    identity = ENV.fetch('SIGNING_IDENTITY', '')
    profile = ENV.fetch('NOTARYTOOL_PROFILE', '')
    raise 'Set SIGNING_IDENTITY and NOTARYTOOL_PROFILE (see readme).' if identity.empty? || identity == '-' || profile.empty?
    identities = run('security', 'find-identity', '-v', '-p', 'codesigning')
    unless identities.lines.any? { |line| line.include?(identity) && line.include?('Developer ID Application:') }
      raise 'SIGNING_IDENTITY must match a valid Developer ID Application certificate.'
    end
    run('xcrun', 'notarytool', 'history', '--keychain-profile', profile, '--output-format', 'json')
  end

  def build(signed: false)
    current = version
    command = %w[swift build --configuration release --product MathReduce --arch arm64 --arch x86_64 --force-resolved-versions]
    run(*command)
    binary_directory = run(*command, '--show-bin-path')
    bundle = path('dist/MathReduce.service')
    FileUtils.rm_rf(bundle)
    contents = File.join(bundle, 'Contents')
    FileUtils.mkdir_p(["#{contents}/MacOS", "#{contents}/Resources"])
    binary = "#{contents}/MacOS/MathReduce"
    FileUtils.cp(File.join(binary_directory, 'MathReduce'), binary, preserve: true)
    FileUtils.cp(path('Resources/Info.plist'), "#{contents}/Info.plist")
    FileUtils.cp(path('license.txt'), "#{contents}/Resources/MathReduce-LICENSE.txt")
    FileUtils.cp(path('Resources/DDMathParser-LICENSE.txt'), "#{contents}/Resources/DDMathParser-LICENSE.txt")
    run('xcrun', 'lipo', binary, '-verify_arch', 'arm64', 'x86_64')
    signing = signed ? ['--options', 'runtime', '--timestamp'] : []
    run('codesign', '--force', '--sign', signed ? ENV.fetch('SIGNING_IDENTITY') : '-', *signing, bundle)
    run('codesign', '--verify', '--strict', '--verbose=2', bundle)
    raise 'The bundled executable failed its smoke test.' unless run(binary, '--evaluate', '2**10') == '1024'
    raise 'The bundled executable reports the wrong version.' unless run(binary, '--version') == current
    bundle
  end

  def package
    receipt = state
    raise 'An unfinished release exists. Run just resume before packaging again.' if receipt && !receipt['complete']

    check_signing
    bundle = build(signed: true)
    dmg = path("dist/#{asset_name}")
    Dir.mktmpdir('math-reduce-package-') do |staging|
      run('ditto', bundle, File.join(staging, File.basename(bundle)))
      FileUtils.cp(path('readme.md'), staging)
      run('hdiutil', 'create', '-ov', '-format', 'UDZO', '-volname', 'Math Reduce', '-srcfolder', staging, dmg)
    end
    run('codesign', '--force', '--sign', ENV.fetch('SIGNING_IDENTITY'), '--timestamp', dmg)
    # fastlane's notarize action cannot use a notarytool Keychain profile.
    response = run('xcrun', 'notarytool', 'submit', dmg, '--keychain-profile', ENV.fetch('NOTARYTOOL_PROFILE'),
                   '--wait', '--timeout', '30m', '--output-format', 'json')
    File.write(path('dist/notarization.json'), response + "\n")
    raise 'Notarization was not accepted. See dist/notarization.json.' unless JSON.parse(response)['status'] == 'Accepted'
    # Apple supports stapling DMGs, not standalone .service bundles.
    run('xcrun', 'stapler', 'staple', dmg)
    run('xcrun', 'stapler', 'validate', dmg)
    run('codesign', '--verify', '--strict', dmg)
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
    File.write(dmg + '.sha256', "#{digest(dmg)}  #{File.basename(dmg)}\n")
    dmg
  end

  def install(bundle)
    destination = File.expand_path('~/Library/Services/MathReduce.service')
    raise "An installation already exists at #{destination}. Run just uninstall first." if File.exist?(destination) || File.symlink?(destination)
    run('ditto', bundle, destination)
    run(File.join(destination, 'Contents/MacOS/MathReduce'), '--refresh-services')
  end

  def homebrew
    FastlaneCore::Helper.which('brew')
  end

  def service_directories
    [File.expand_path('~/Library/Services'), '/Library/Services']
  end

  def math_reduce_service?(bundle)
    # A dangling link has no plist to inspect, but its canonical name is unambiguous.
    return File.basename(bundle) == 'MathReduce.service' if File.symlink?(bundle) && !File.exist?(bundle)

    plist = File.join(bundle, 'Contents/Info.plist')
    return false unless File.file?(plist)

    info = CFPropertyList.native_types(CFPropertyList::List.new(file: plist).value)
    info.is_a?(Hash) && info['CFBundleIdentifier'] == 'com.kitschpatrol.MathReduce'
  rescue StandardError => error
    FastlaneCore::UI.important("Skipping unreadable service #{bundle}: #{error.message}")
    false
  end

  def remove_service(bundle)
    FastlaneCore::UI.message("Removing #{bundle}")
    FileUtils.remove_entry(bundle)
  rescue Errno::EACCES, Errno::EPERM
    # Elevate only the deletion that needs it, keeping Homebrew and the refresh
    # under the current user. rm removes a bundle symlink without following it.
    run('sudo', '/bin/rm', '-R', '--', bundle)
  end

  def uninstall
    brew = homebrew
    if brew && run(brew, 'list', '--cask', '-1', log: false).lines.map(&:strip).include?('math-reduce')
      run(brew, 'uninstall', '--cask', 'math-reduce')
    end
    service_directories.each do |directory|
      next unless File.directory?(directory)

      Dir.children(directory).sort.each do |name|
        next unless name.end_with?('.service')

        bundle = File.join(directory, name)
        remove_service(bundle) if math_reduce_service?(bundle)
      end
    end
    # Use AppKit directly so uninstall needs neither a build nor an installed binary.
    run('/usr/bin/osascript', '-l', 'JavaScript', '-e', 'ObjC.import("AppKit"); $.NSUpdateDynamicServices();')
    FastlaneCore::UI.success('Math Reduce uninstalled. Quit and reopen apps to refresh their Services menus.')
  end

  def state
    file = path('dist/release-state.json')
    File.file?(file) ? JSON.parse(File.read(file)) : nil
  end

  def save_state(value)
    FileUtils.mkdir_p(path('dist'))
    temporary = path('dist/release-state.tmp')
    File.write(temporary, JSON.pretty_generate(value) + "\n")
    File.rename(temporary, path('dist/release-state.json'))
  end

  def verify_state(value)
    raise 'Unsupported release state. Expected a fastlane release receipt.' unless value['schema'] == 1
    unless value['repository'] == repository && value['version'] == version
      raise 'Repository or Info.plist version differs from the interrupted release.'
    end
    raise 'Switch back to the release branch before resuming.' unless run('git', 'branch', '--show-current') == value['branch']
    unless value['asset'] == asset_name && digest(path("dist/#{value['asset']}")) == value['sha256']
      raise 'The release artifact changed; refusing to publish it.'
    end
    VERSION_FILES.each do |file|
      raise "#{file} changed since the release was built." unless digest(path(file)) == value.fetch('files').fetch(file)
    end
    check_origin
  end

  def verify_github_asset(value, expected_sha:)
    validate_version(value)
    release = JSON.parse(run('gh', 'release', 'view', "v#{value}", '--repo', repository, '--json', 'isDraft,isPrerelease,assets'))
    raise 'Expected a published, stable GitHub release.' if release['isDraft'] || release['isPrerelease']
    name = asset_name(value)
    raise "The release must contain exactly one #{name}." unless release['assets'].count { |asset| asset['name'] == name } == 1
    sha = Dir.mktmpdir('math-reduce-download-') do |directory|
      run('gh', 'release', 'download', "v#{value}", '--repo', repository, '--pattern', name, '--dir', directory)
      digest(File.join(directory, name))
    end
    raise 'The uploaded release asset differs from the signed local artifact.' unless sha == expected_sha
  end
end
