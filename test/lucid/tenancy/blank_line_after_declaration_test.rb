require "test_helper"
require "lucid/tenancy/rubocop"

class BlankLineAfterDeclarationTest < Minitest::Test
  COP = RuboCop::Cop::Lucid::Tenancy::BlankLineAfterDeclaration

  def investigate(source)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
    cop = COP.new(RuboCop::Config.new, autocorrect: true)
    report = RuboCop::Cop::Commissioner.new([cop]).investigate(processed)
    corrector = RuboCop::Cop::Corrector.new(processed)
    report.correctors.compact.each { |item| corrector.merge!(item) }
    [report.offenses, corrector.rewrite]
  end

  def test_declaration_followed_by_code_is_an_offense
    # arrange
    source = "class A < ActiveRecord::Migration[7.2]\n  tenancy :tenant\n  def change; end\nend\n"

    # act
    offenses, = investigate(source)

    # assert
    assert_equal 1, offenses.size
    assert_equal 2, offenses.first.line
    assert_includes offenses.first.message, COP::MSG
  end

  def test_declaration_followed_by_blank_line_is_clean
    # arrange
    source = "class A < ActiveRecord::Migration[7.2]\n  tenancy :shared\n\n  def change; end\nend\n"

    # act
    offenses, = investigate(source)

    # assert
    assert_empty offenses
  end

  def test_autocorrect_inserts_the_blank_line
    # arrange
    source = "class A < ActiveRecord::Migration[7.2]\n  tenancy :tenant\n  def change; end\nend\n"

    # act
    _, corrected = investigate(source)

    # assert
    assert_equal "class A < ActiveRecord::Migration[7.2]\n  tenancy :tenant\n\n  def change; end\nend\n", corrected
  end

  def test_declaration_at_the_end_of_the_file_is_clean
    # arrange
    source = "tenancy :tenant"

    # act
    offenses, = investigate(source)

    # assert
    assert_empty offenses
  end

  def test_declaration_on_the_last_line_with_trailing_newline_is_clean
    # arrange
    source = "tenancy :tenant\n"

    # act
    offenses, = investigate(source)

    # assert
    assert_empty offenses
  end

  def test_call_with_a_receiver_is_ignored
    # arrange
    source = "obj.tenancy :x\nputs 1\n"

    # act
    offenses, = investigate(source)

    # assert
    assert_empty offenses
  end

  def test_other_methods_are_ignored
    # arrange
    source = "other :tenant\nputs 1\n"

    # act
    offenses, = investigate(source)

    # assert
    assert_empty offenses
  end

  def test_default_configuration_enables_the_cop_for_migrations
    # arrange
    config = RuboCop::ConfigLoader.default_configuration

    # act
    cop_config = config.for_cop("Lucid/Tenancy/BlankLineAfterDeclaration")

    # assert
    assert cop_config["Enabled"]
    assert_includes cop_config["Include"], "db/migrate/**/*.rb"
  end

  def test_requiring_the_gem_alone_does_not_load_rubocop
    # arrange
    lib = File.expand_path("../../../lib", __dir__)
    script = 'require "lucid/tenancy"; print defined?(RuboCop).inspect'

    # act
    output = IO.popen({ "BUNDLE_GEMFILE" => File.expand_path("../../../Gemfile", __dir__) }, ["bundle", "exec", "ruby", "-I", lib, "-e", script], err: File::NULL, &:read)

    # assert
    assert_equal "nil", output
  end
end
