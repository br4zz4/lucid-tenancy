require "test_helper"
require "action_cable"
require "action_dispatch"
require "rack/mock"

class ActionCableTest < TenancyTest
  class RecordingSubscriptions
    attr_reader :payloads

    def initialize(&on_execute)
      @payloads = []
      @on_execute = on_execute
    end

    def execute_command(payload)
      @payloads << payload
      @on_execute&.call(payload)
    end
  end

  FakeServer = Struct.new(:worker_pool, :config, :logger, :event_loop, keyword_init: true)

  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "TtOrganization"
      config.base_domain = "app.test"
    end
    @alfa = provision_tenant(TtOrganization, "alfa")
    @beta = provision_tenant(TtOrganization, "beta")
    @connection_class = Class.new(ActionCable::Connection::Base) { include Lucid::Tenancy::ActionCable }
  end

  def build_connection(host)
    logger = Logger.new(nil)
    server = FakeServer.new(worker_pool: nil, config: ActionCable::Server::Configuration.new.tap { |c| c.logger = logger }, logger: logger)
    env = Rack::MockRequest.env_for("http://#{host}/cable")
    @connection_class.new(server, env)
  end

  def run_command(connection, &block)
    connection.instance_variable_set(:@subscriptions, RecordingSubscriptions.new(&block))
    connection.send(:handle_channel_command, { "command" => "message" })
  end

  def test_including_declares_the_tenant_identifier_and_the_command_callback
    # arrange
    klass = @connection_class

    # act
    callbacks = klass._command_callbacks.map(&:kind)

    # assert
    assert_includes klass.identifiers, :tenant_identifier
    assert_equal [:around], callbacks
  end

  def test_connect_sets_tenant_identifier_from_the_host
    # arrange
    connection = build_connection("alfa.app.test")

    # act
    connection.connect

    # assert
    assert_equal "alfa", connection.tenant_identifier
  end

  def test_connect_without_tenant_host_leaves_identifier_nil
    # arrange
    connection = build_connection("www.other.test")

    # act
    connection.connect

    # assert
    assert_nil connection.tenant_identifier
  end

  def test_connect_uses_custom_resolver
    # arrange
    Lucid::Tenancy.configure { |config| config.resolver = ->(_request) { "alfa" } }
    connection = build_connection("whatever.test")

    # act
    connection.connect

    # assert
    assert_equal "alfa", connection.tenant_identifier
  end

  def test_tenant_is_active_during_the_command_and_restored_afterwards
    # arrange
    connection = build_connection("alfa.app.test")
    connection.connect
    seen = nil

    # act
    run_command(connection) { seen = [Lucid::Tenancy.current&.schema_name, current_schema] }

    # assert
    assert_equal [@alfa.schema_name, @alfa.schema_name], seen
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_previous_tenant_is_restored_after_the_command
    # arrange
    connection = build_connection("alfa.app.test")
    connection.connect
    Lucid::Tenancy.set(tenant: @beta)

    # act
    run_command(connection) {}

    # assert
    assert_same @beta, Lucid::Tenancy.current
    assert_equal @beta.schema_name, current_schema
  end

  def test_tenant_is_restored_even_when_the_command_raises
    # arrange
    connection = build_connection("alfa.app.test")
    connection.connect
    Lucid::Tenancy.set(tenant: @beta)

    # act
    error = assert_raises(RuntimeError) { run_command(connection) { raise "boom" } }

    # assert
    assert_equal "boom", error.message
    assert_same @beta, Lucid::Tenancy.current
    assert_equal @beta.schema_name, current_schema
  end

  def test_command_without_identifier_runs_in_shared_even_if_the_worker_was_in_a_tenant
    # arrange
    connection = build_connection("www.other.test")
    connection.connect
    Lucid::Tenancy.set(tenant: @beta)
    seen = nil

    # act
    run_command(connection) { seen = [Lucid::Tenancy.current, current_schema] }

    # assert
    assert_equal [nil, "public"], seen
    assert_same @beta, Lucid::Tenancy.current
    assert_equal @beta.schema_name, current_schema
  end

  def test_command_payload_reaches_the_subscriptions
    # arrange
    connection = build_connection("alfa.app.test")
    connection.connect
    subscriptions = nil

    # act
    run_command(connection) { subscriptions = connection.subscriptions }

    # assert
    assert_equal [{ "command" => "message" }], subscriptions.payloads
  end
end
