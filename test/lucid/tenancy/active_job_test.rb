require "test_helper"
require "active_job"

ActiveJob::Base.include(Lucid::Tenancy::ActiveJobExtension) unless ActiveJob::Base < Lucid::Tenancy::ActiveJobExtension

class ActiveJobTest < TenancyTest
  KEY = Lucid::Tenancy::ActiveJobExtension::KEY

  def setup
    super
    use_dump(VALID_DUMP)
    define_tenant_model
    Lucid::Tenancy.configure { |config| config.tenant_model = "TtOrganization" }
    @alfa = provision_tenant(TtOrganization, "alfa")
    @beta = provision_tenant(TtOrganization, "beta")
    @previous_logger = ActiveJob::Base.logger
    ActiveJob::Base.logger = Logger.new(nil)
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @seen = []
    Thread.current[:tt_job_seen] = @seen
  end

  def teardown
    Thread.current[:tt_job_seen] = nil
    ActiveJob::Base.queue_adapter = @previous_adapter
    ActiveJob::Base.logger = @previous_logger
    super
  end

  def define_job(name, mode: nil, fail_with: nil)
    klass = Class.new(ActiveJob::Base)
    klass.tenancy(mode) if mode
    klass.define_method(:perform) do |name_arg = nil|
      schema = ActiveRecord::Base.lease_connection.select_value("SELECT current_schema()")
      Thread.current[:tt_job_seen] << schema
      if name_arg
        ActiveRecord::Base.lease_connection.execute("INSERT INTO students (name) VALUES ('#{name_arg}')")
        Thread.current[:tt_job_seen] << ActiveRecord::Base.lease_connection.select_values("SELECT name FROM students")
      end
      raise fail_with if fail_with
    end
    Object.const_set(name, klass)
    @test_constants << name
    klass
  end

  def student_names(tenant)
    connection.select_values(%(SELECT name FROM "#{tenant.schema_name}".students))
  end

  def run_elsewhere(payload)
    Thread.new do
      Thread.current[:tt_job_seen] = @seen
      ActiveJob::Base.execute(payload)
    end.join
  end

  def test_job_enqueued_inside_tenant_serializes_the_schema
    # arrange
    job_class = define_job("TtTenantJob")

    # act
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new.serialize }

    # assert
    assert_equal "alfa", payload[KEY]
  end

  def test_job_runs_in_the_tenant_schema_from_another_thread_without_current_tenant
    # arrange
    job_class = define_job("TtTenantJob")
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new("ana").serialize }

    # act
    run_elsewhere(payload)

    # assert
    assert_equal [@alfa.schema_name, ["ana"]], @seen
    assert_equal ["ana"], student_names(@alfa)
    assert_empty student_names(@beta)
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_perform_enqueued_jobs_runs_in_the_enqueue_tenant
    # arrange
    job_class = define_job("TtTenantJob")
    helper = Class.new(ActiveJob::TestCase).new("x")

    # act
    helper.perform_enqueued_jobs do
      Lucid::Tenancy.with(tenant: @beta) { job_class.perform_later("bia") }
    end

    # assert
    assert_equal [@beta.schema_name, ["bia"]], @seen
    assert_equal ["bia"], student_names(@beta)
    assert_equal "public", current_schema
  end

  def test_job_restores_previous_schema_after_running
    # arrange
    job_class = define_job("TtTenantJob")
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new.serialize }
    Lucid::Tenancy.set(tenant: @beta)

    # act
    ActiveJob::Base.execute(payload)

    # assert
    assert_equal [@alfa.schema_name], @seen
    assert_same @beta, Lucid::Tenancy.current
    assert_equal @beta.schema_name, current_schema
  end

  def test_job_restores_previous_schema_when_it_raises
    # arrange
    job_class = define_job("TtFailingJob", fail_with: "boom")
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new.serialize }
    Lucid::Tenancy.set(tenant: @beta)

    # act
    error = assert_raises(RuntimeError) { ActiveJob::Base.execute(payload) }

    # assert
    assert_equal "boom", error.message
    assert_same @beta, Lucid::Tenancy.current
    assert_equal @beta.schema_name, current_schema
  end

  def test_job_enqueued_outside_tenant_runs_in_shared
    # arrange
    job_class = define_job("TtTenantJob")
    payload = job_class.new.serialize
    Lucid::Tenancy.set(tenant: @alfa)

    # act
    ActiveJob::Base.execute(payload)

    # assert
    refute payload.key?(KEY)
    assert_equal ["public"], @seen
    assert_same @alfa, Lucid::Tenancy.current
  end

  def test_perform_now_created_inside_a_tenant_runs_in_that_tenant
    # arrange
    job_class = define_job("TtTenantJob")

    # act
    Lucid::Tenancy.with(tenant: @alfa) { job_class.new("ana").perform_now }

    # assert
    assert_equal [@alfa.schema_name, ["ana"]], @seen
    assert_equal "public", current_schema
  end

  def test_perform_now_created_in_a_tenant_runs_there_even_when_called_inside_another
    # arrange
    job_class = define_job("TtTenantJob")
    job = Lucid::Tenancy.with(tenant: @alfa) { job_class.new }

    # act
    Lucid::Tenancy.with(tenant: @beta) { job.perform_now }

    # assert
    assert_equal [@alfa.schema_name], @seen
  end

  def test_deserialized_job_outside_tenant_runs_in_shared_even_if_worker_is_in_a_tenant
    # arrange
    job_class = define_job("TtTenantJob")
    payload = job_class.new.serialize

    # act
    Lucid::Tenancy.with(tenant: @beta) { ActiveJob::Base.execute(payload) }

    # assert
    assert_equal ["public"], @seen
  end

  def test_shared_job_runs_in_public_and_does_not_serialize_the_tenant
    # arrange
    job_class = define_job("TtSharedJob", mode: :shared)

    # act
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new.serialize }
    run_elsewhere(payload)

    # assert
    refute payload.key?(KEY)
    assert_equal ["public"], @seen
  end

  def test_shared_job_runs_in_public_even_when_executed_inside_a_tenant
    # arrange
    job_class = define_job("TtSharedJob", mode: :shared)
    payload = job_class.new.serialize
    Lucid::Tenancy.set(tenant: @alfa)

    # act
    ActiveJob::Base.execute(payload)

    # assert
    assert_equal ["public"], @seen
    assert_same @alfa, Lucid::Tenancy.current
  end

  def test_invalid_tenancy_mode_raises_argument_error
    # arrange
    job_class = Class.new(ActiveJob::Base)

    # act & assert
    assert_raises(ArgumentError) { job_class.tenancy(:other) }
  end

  def test_tenancy_mode_defaults_to_tenant_and_is_inherited_per_class
    # arrange
    shared = define_job("TtSharedJob", mode: :shared)
    plain = define_job("TtPlainJob")

    # act & assert
    assert_equal :tenant, plain.tenancy_mode
    assert_equal :shared, shared.tenancy_mode
    assert_equal :tenant, ActiveJob::Base.tenancy_mode
  end

  def test_removed_tenant_between_enqueue_and_execute_raises_tenant_not_found
    # arrange
    job_class = define_job("TtTenantJob")
    payload = Lucid::Tenancy.with(tenant: @alfa) { job_class.new.serialize }
    @alfa.drop
    TtOrganization.where(id: @alfa.id).delete_all

    # act
    error = assert_raises(Lucid::Tenancy::Error::TenantNotFound) { ActiveJob::Base.execute(payload) }

    # assert
    assert_match(/#{@alfa.schema_name}/, error.message)
    assert_nil Lucid::Tenancy.current
    assert_equal "public", current_schema
  end

  def test_tenant_with_hyphenated_identifier_serializes_identifier_and_runs_in_its_schema
    # arrange
    job_class = define_job("TtTenantJob")
    hyphen = provision_tenant(TtOrganization, "escola-alfa")
    payload = Lucid::Tenancy.with(tenant: hyphen) { job_class.new.serialize }

    # act
    run_elsewhere(payload)

    # assert
    assert_equal "escola-alfa", payload[KEY]
    assert_equal ["escola_alfa"], @seen
    assert_equal "public", current_schema
  end
end
