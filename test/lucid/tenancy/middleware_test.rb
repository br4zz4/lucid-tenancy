require "test_helper"
require "rack/mock"
require "lucid/tenancy/railtie"

class MiddlewareTest < TenancyTest
  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure do |config|
      config.tenant_model = "TtOrganization"
      config.base_domain = "app.test"
      config.shared_paths = ["/health", "/admin"]
      config.trusted_proxies = ["127.0.0.1"]
    end
    @acme = provision_tenant(TtOrganization, "acme")
    @globex = provision_tenant(TtOrganization, "globex")
  end

  def probe
    lambda do |_env|
      payload = [Lucid::Tenancy.current&.schema_name.to_s, current_schema].join("|")
      [200, { "content-type" => "text/plain" }, [payload]]
    end
  end

  def get(app, path, host, extra = {})
    env = Rack::MockRequest.env_for("http://#{host}#{path}", extra)
    app.call(env)
  end

  def read(response)
    status, _headers, body = response
    content = +""
    body.each { |chunk| content << chunk }
    body.close if body.respond_to?(:close)
    [status, content]
  end

  def test_request_runs_in_the_tenant_schema_and_returns_to_shared_on_close
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    status, body = read(get(app, "/", "acme.app.test"))

    # assert
    assert_equal 200, status
    assert_equal "#{@acme.schema_name}|#{@acme.schema_name}", body
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_tenant_is_still_active_while_the_body_is_streamed
    # arrange
    streaming = lambda do |_env|
      body = Enumerator.new do |yielder|
        yielder << "#{Lucid::Tenancy.current&.schema_name}|#{current_schema}"
        yielder << "#{Lucid::Tenancy.current&.schema_name}|#{current_schema}"
      end
      [200, {}, body]
    end
    app = Lucid::Tenancy::Middleware.new(streaming)

    # act
    _status, _headers, body = get(app, "/", "acme.app.test")
    during = Lucid::Tenancy.current&.schema_name
    chunks = []
    body.each { |chunk| chunks << chunk }
    before_close = current_schema
    body.close
    after_close = current_schema

    # assert
    assert_equal @acme.schema_name, during
    assert_equal ["#{@acme.schema_name}|#{@acme.schema_name}"] * 2, chunks
    assert_equal @acme.schema_name, before_close
    assert_equal "public", after_close
    assert_nil Lucid::Tenancy.current
  end

  def test_missing_tenant_is_answered_by_the_default_404
    # arrange
    called = false
    app = Lucid::Tenancy::Middleware.new(->(_env) { called = true; [200, {}, ["ok"]] })

    # act
    status, body = read(get(app, "/", "nobody.app.test"))

    # assert
    assert_equal 404, status
    assert_equal "Not Found", body
    refute called
    assert_nil Lucid::Tenancy.current
  end

  def test_missing_tenant_uses_the_configured_handler
    # arrange
    Lucid::Tenancy.configuration.on_missing_tenant = ->(_env) { [410, {}, ["gone"]] }
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    status, body = read(get(app, "/", "nobody.app.test"))

    # assert
    assert_equal 410, status
    assert_equal "gone", body
  end

  def test_shared_path_runs_without_tenant
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    status, body = read(get(app, "/health", "acme.app.test"))

    # assert
    assert_equal 200, status
    assert_equal "|public", body
  end

  def test_shared_path_prefix_matches_on_a_path_boundary
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    nested = read(get(app, "/admin/users", "acme.app.test"))
    lookalike = read(get(app, "/administrator", "acme.app.test"))
    lookalike_health = read(get(app, "/healthy", "nobody.app.test"))

    # assert
    assert_equal "|public", nested.last
    assert_equal "#{@acme.schema_name}|#{@acme.schema_name}", lookalike.last
    assert_equal 404, lookalike_health.first
  end

  def test_host_without_tenant_runs_in_the_shared_schema
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    bare = read(get(app, "/", "app.test"))
    foreign = read(get(app, "/", "example.org"))

    # assert
    assert_equal "|public", bare.last
    assert_equal "|public", foreign.last
  end

  def test_forwarded_host_from_a_trusted_proxy_selects_the_tenant
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    _status, body = read(get(app, "/", "internal.local", "REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_HOST" => "globex.app.test"))

    # assert
    assert_equal "#{@globex.schema_name}|#{@globex.schema_name}", body
  end

  def test_forwarded_host_from_an_untrusted_address_is_ignored
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    _status, body = read(get(app, "/", "acme.app.test", "REMOTE_ADDR" => "203.0.113.9", "HTTP_X_FORWARDED_HOST" => "globex.app.test"))

    # assert
    assert_equal "#{@acme.schema_name}|#{@acme.schema_name}", body
  end

  def test_custom_resolver_selects_the_tenant
    # arrange
    Lucid::Tenancy.configuration.resolver = ->(request) { request.get_header("HTTP_X_TENANT") }
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    _status, body = read(get(app, "/", "whatever.test", "HTTP_X_TENANT" => "globex"))

    # assert
    assert_equal "#{@globex.schema_name}|#{@globex.schema_name}", body
  end

  def test_exception_in_the_app_returns_to_shared_and_reraises
    # arrange
    failing = ->(_env) { raise ArgumentError, "boom" }
    app = Lucid::Tenancy::Middleware.new(failing)

    # act
    error = assert_raises(ArgumentError) { get(app, "/", "acme.app.test") }

    # assert
    assert_equal "boom", error.message
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_no_tenant_leaks_between_consecutive_requests
    # arrange
    app = Lucid::Tenancy::Middleware.new(probe)

    # act
    first = read(get(app, "/", "acme.app.test"))
    second = read(get(app, "/", "globex.app.test"))
    third = read(get(app, "/", "app.test"))

    # assert
    assert_equal "#{@acme.schema_name}|#{@acme.schema_name}", first.last
    assert_equal "#{@globex.schema_name}|#{@globex.schema_name}", second.last
    assert_equal "|public", third.last
  end

  def test_railtie_registers_the_middleware_initializer
    # arrange
    names = Lucid::Tenancy::Railtie.initializers.map(&:name)

    # act
    registered = names.include?("lucid_tenancy.middleware")

    # assert
    assert registered
  end
end
