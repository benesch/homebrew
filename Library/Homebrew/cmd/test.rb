require "extend/ENV"
require "timeout"
require "debrew"
require "formula_assertions"

module Homebrew
  TEST_TIMEOUT_SECONDS = 5*60

  def test
    raise FormulaUnspecifiedError if ARGV.named.empty?

    ENV.extend(Stdenv)
    ENV.setup_build_environment

    ARGV.formulae.each do |f|
      # Cannot test uninstalled formulae
      unless f.installed?
        ofail "Testing requires the latest version of #{f.name}"
        next
      end

      # Cannot test formulae without a test method
      unless f.test_defined?
        ofail "#{f.name} defines no test"
        next
      end

      f.requirements.to_a.delete_if(&:satisfied?).each do |req|
        onoe req.message("test")
        Homebrew.failed = true if req.fatal?
      end

      missing_test_deps = f.deps.test.delete_if { |d| d.satisfied?([]) }
      if missing_test_deps.any?
        ofail <<-EOS.undent
          #{f.name} is missing test dependencies.

          You can `brew install` these dependencies:
              brew install #{missing_test_deps.sort_by(&:name) * " "}
        EOS
      end

      next if Homebrew.failed

      puts "Testing #{f.name}"

      f.extend(Assertions)
      f.extend(Debrew::Formula) if ARGV.debug?

      env = ENV.to_hash

      begin
        # tests can also return false to indicate failure
        Timeout::timeout TEST_TIMEOUT_SECONDS do
          raise "test returned false" if f.run_test == false
        end
      rescue Assertions::FailedAssertion => e
        ofail "#{f.name}: failed"
        puts e.message
      rescue Exception => e
        ofail "#{f.name}: failed"
        puts e, e.backtrace
      ensure
        ENV.replace(env)
      end
    end
  end
end
