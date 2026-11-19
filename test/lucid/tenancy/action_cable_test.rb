require "test_helper"
require "rack/mock"
require "rack/request"
require "lucid/tenancy/action_cable"

class ActionCableTest < TenancyTest
  class FakeBase
    class << self
      def identifiers
        @identifiers ||= []
      end

      def before_commands
        @before_commands ||= []
      end

      def after_commands
        @after_commands ||= []
      end

      def identified_by(*names)
        identifiers.concat(names)
        attr_accessor(*names)
      end

      def before_command(&block)
        before_commands << block
      end

      def after_command(&block)
        after_commands << block
      end
    end

    attr_reader :request, :connected

    def initialize(request)
      @request = request
    end

    def connect
      @connected = true
    end

    def run_command
      self.class.before_commands.each { |callback| instance_exec(&callback) }
      yield
    ensure
      self.class.after_commands.each { |callback| instance_exec(&callback) }
    end
  end

  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "TtOrganization"
      config.base_domain = "app.test"
    end
    @alfa = provision_tenant(TtOrganization, "alfa")
    @connection_class = Class.new(FakeBase) { include Lucid::Tenancy::ActionCable }
  end

  def request_for(host)
    Rack::Request.new(Rack::MockRequest.env_for("http://#{host}/cable"))
  end

  def test_including_declares_tenant_identifier_and_command_callbacks
    # arrange
    klass = @connection_class

    # act & assert
    assert_equal [:tenant_identifier], klass.identifiers
    assert_equal 1, klass.before_commands.size
    assert_equal 1, klass.after_commands.size
  end

  def test_connect_sets_tenant_identifier_from_the_host
    # arrange
    connection = @connection_class.new(request_for("alfa.app.test"))

    # act
    connection.connect

    # assert
    assert_equal "alfa", connection.tenant_identifier
    assert connection.connected
  end

  def test_connect_without_tenant_host_leaves_identifier_nil
    # arrange
    connection = @connection_class.new(request_for("www.other.test"))

    # act
    connection.connect

    # assert
    assert_nil connection.tenant_identifier
  end

  def test_connect_uses_custom_resolver
    # arrange
    Lucid::Tenancy.configure { |config| config.resolver = ->(_request) { "alfa" } }
    connection = @connection_class.new(request_for("whatever.test"))

    # act
    connection.connect

    # assert
    assert_equal "alfa", connection.tenant_identifier
  end

  def test_command_runs_in_the_tenant_and_clears_it_afterwards
    # arrange
    connection = @connection_class.new(request_for("alfa.app.test"))
    connection.connect
    seen = nil

    # act
    connection.run_command { seen = [Lucid::Tenancy.current&.schema_name, current_schema] }

    # assert
    assert_equal [@alfa.schema_name, @alfa.schema_name], seen
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_command_clears_the_tenant_even_when_it_raises
    # arrange
    connection = @connection_class.new(request_for("alfa.app.test"))
    connection.connect

    # act
    assert_raises(RuntimeError) { connection.run_command { raise "boom" } }

    # assert
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_command_without_tenant_identifier_stays_in_shared
    # arrange
    connection = @connection_class.new(request_for("www.other.test"))
    connection.connect
    seen = nil

    # act
    connection.run_command { seen = [Lucid::Tenancy.current, current_schema] }

    # assert
    assert_equal [nil, "public"], seen
  end
end
