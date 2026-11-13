# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../lib/foxyn_installer/system_copy'

def assert(value, message)
  raise message unless value
end

def rejected
  yield
  raise 'unsafe copy accepted'
rescue ArgumentError
end

Dir.mktmpdir('foxyn-copy-test') do |tmp|
  source = File.join(tmp, 'source')
  target = File.join(tmp, 'target')
  Dir.mkdir(source)
  Dir.mkdir(target)
  %w[bin etc var].each { |name| Dir.mkdir(File.join(source, name)) }
  File.write(File.join(source, 'bin', 'app'), 'fixture')

  called = []
  fail_on_etc = lambda do |_program, src, dest|
    name = File.basename(src)
    called << name
    name == 'etc' ? [false, 'injected copy failure'] : (FileUtils.cp_r(src, dest); [true, ''])
  end
  events = []
  begin
    FoxynInstaller::SystemCopy.new(run: fail_on_etc).copy(source: source, target: target, progress: ->(e) { events << e })
    raise 'failed copy reported success'
  rescue FoxynInstaller::SystemCopy::Error => e
    assert(e.directory == 'etc' && e.message.include?('injected copy failure'), 'missing actionable failure')
  end
  assert(called == %w[bin etc] && !File.exist?(File.join(target, 'var')), 'copy did not stop after failure')
  assert(events.last == { 'directory' => 'etc', 'state' => 'started' }, 'failure was marked complete')
  rejected { FoxynInstaller::SystemCopy.new(run: fail_on_etc).copy(source: source, target: target) }
  rejected { FoxynInstaller::SystemCopy.new(run: fail_on_etc).copy(source: source, target: source) }
  nested = File.join(source, 'bin', 'nested-target')
  Dir.mkdir(nested)
  rejected { FoxynInstaller::SystemCopy.new(run: fail_on_etc).copy(source: source, target: nested) }
  Dir.rmdir(nested)
  empty = File.join(tmp, 'empty-target')
  Dir.mkdir(empty)
  symlink = File.join(tmp, 'target-link')
  File.symlink(empty, symlink)
  rejected { FoxynInstaller::SystemCopy.new(run: fail_on_etc).copy(source: source, target: symlink) }

  File.link(File.join(source, 'bin', 'app'), File.join(source, 'etc', 'app-crosslink'))
  FileUtils.rm_rf(target)
  Dir.mkdir(target)
  copy_fixture = lambda do |_program, src, dest|
    FileUtils.cp_r(src, dest)
    [true, '']
  end
  FoxynInstaller::SystemCopy.new(run: copy_fixture).copy(source: source, target: target)
  assert(File.identical?(File.join(target, 'bin', 'app'), File.join(target, 'etc', 'app-crosslink')),
         'cross-directory hardlink not restored')

  FileUtils.rm_rf(target)
  Dir.mkdir(target)
  corrupt_fixture = lambda do |_program, src, dest|
    FileUtils.cp_r(src, dest)
    File.write(File.join(dest, 'app-crosslink'), 'different') if File.basename(src) == 'etc'
    [true, '']
  end
  begin
    FoxynInstaller::SystemCopy.new(run: corrupt_fixture).copy(source: source, target: target)
    raise 'mismatched content accepted'
  rescue FoxynInstaller::SystemCopy::Error => e
    assert(e.message.include?('contents differ'), 'mismatched content not reported')
  end
  assert(File.read(File.join(target, 'etc', 'app-crosslink')) == 'different', 'mismatched data overwritten')

  if File.executable?('/bin/cpdup') && RUBY_PLATFORM.include?('dragonfly')
    FileUtils.rm_rf(target)
    Dir.mkdir(target)
    File.symlink('app', File.join(source, 'bin', 'app-link'))
    File.link(File.join(source, 'bin', 'app'), File.join(source, 'bin', 'app-hardlink'))
    File.chmod(0o755, File.join(source, 'bin', 'app'))
    result = FoxynInstaller::SystemCopy.new.copy(source: source, target: target)
    app = File.join(target, 'bin', 'app')
    assert(result['copied_directories'] == %w[bin etc var], 'unexpected directory list')
    assert(File.read(app) == 'fixture', 'copied contents differ')
    assert(File.symlink?(File.join(target, 'bin', 'app-link')), 'symlink not preserved')
    assert(File.stat(app).ino == File.stat(File.join(target, 'bin', 'app-hardlink')).ino, 'hardlink not preserved')
    assert(File.stat(app).ino == File.stat(File.join(target, 'etc', 'app-crosslink')).ino, 'cross-directory hardlink not preserved')
    assert((File.stat(app).mode & 0o777) == 0o755, 'executable mode not preserved')
    puts 'Real cpdup disposable-tree test passed'
  else
    puts 'Real cpdup test skipped: requires FoxynBSD/DragonFly'
  end
end
puts 'System copy tests passed'
