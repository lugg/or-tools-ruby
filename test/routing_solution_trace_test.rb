require_relative "test_helper"

class RoutingSolutionTraceTest < Minitest::Test
  EMPTY_TRACE = {
    first_solution_ms: nil,
    first_solution_objective: nil,
    best_solution_ms: nil,
    best_solution_objective: nil,
    latest_solution_ms: nil,
    latest_solution_objective: nil,
    solution_count: 0,
    improvement_count: 0,
    objective_improvement: nil,
    samples: [],
    samples_truncated: false
  }.freeze

  MATRIX = begin
    random = Random.new(1234)
    size = 25
    Array.new(size) do |from|
      Array.new(size) do |to|
        from == to ? 0 : random.rand(1..10_000)
      end.freeze
    end.freeze
  end

  def test_records_solution_progress
    routing = build_routing
    trace = routing.enable_solution_trace(
      max_samples: 64,
      sample_interval_ms: 1
    )

    assert_equal EMPTY_TRACE, trace.to_h

    solution = routing.solve_with_parameters(search_parameters(solution_limit: 50))
    values = trace.to_h

    assert_equal solution.objective_value, values[:best_solution_objective]
    assert_operator values[:first_solution_ms], :>=, 0
    assert_operator values[:best_solution_ms], :>=, values[:first_solution_ms]
    assert_operator values[:latest_solution_ms], :>=, values[:first_solution_ms]
    assert_operator values[:first_solution_objective], :>=, values[:best_solution_objective]
    assert_operator values[:latest_solution_objective], :>=, values[:best_solution_objective]
    assert_operator values[:solution_count], :>=, values[:improvement_count] + 1
    assert_equal(
      values[:first_solution_objective] - values[:best_solution_objective],
      values[:objective_improvement]
    )
    assert_operator values[:samples].length, :<=, 64
    refute values[:samples_truncated]
    assert_equal(
      [values[:first_solution_ms], values[:first_solution_objective]],
      values[:samples].first
    )
    assert_equal(
      [values[:best_solution_ms], values[:best_solution_objective]],
      values[:samples].last
    )

    values[:samples].each_cons(2) do |previous, current|
      assert_operator current[0], :>=, previous[0]
      assert_operator current[1], :<, previous[1]
    end
  end

  def test_replaces_improvements_in_the_same_bucket
    routing = build_routing
    trace = routing.enable_solution_trace(
      max_samples: 64,
      sample_interval_ms: 60_000
    )

    solution = routing.solve_with_parameters(search_parameters(solution_limit: 50))
    values = trace.to_h

    assert_equal solution.objective_value, values[:best_solution_objective]
    assert_equal(
      [
        [values[:first_solution_ms], values[:first_solution_objective]],
        [values[:best_solution_ms], values[:best_solution_objective]]
      ],
      values[:samples]
    )
  end

  def test_keeps_aggregates_after_samples_are_truncated
    routing = build_routing
    trace = routing.enable_solution_trace(
      max_samples: 1,
      sample_interval_ms: 1
    )

    solution = routing.solve_with_parameters(search_parameters(solution_limit: 500))
    values = trace.to_h

    assert_equal solution.objective_value, values[:best_solution_objective]
    assert_equal 1, values[:samples].length
    assert values[:samples_truncated]
    assert_operator values[:improvement_count], :>, 1
  end

  def test_native_improvement_limit_stops_search
    baseline_routing = build_routing
    baseline_trace = baseline_routing.enable_solution_trace
    baseline_routing.solve_with_parameters(search_parameters(solution_limit: 500))

    routing = build_routing
    trace = routing.enable_solution_trace
    solution = routing.solve_with_parameters(
      search_parameters(
        solution_limit: 500,
        improvement_limit_parameters: {
          improvement_rate_coefficient: 0.01,
          improvement_rate_solutions_distance: 1
        }
      )
    )

    assert_equal 500, baseline_trace.to_h[:solution_count]
    assert_operator trace.to_h[:solution_count], :<, 500
    assert_equal solution.objective_value, trace.to_h[:best_solution_objective]
  end

  def test_resets_for_warm_solves
    routing = build_routing
    trace = routing.enable_solution_trace(
      max_samples: 64,
      sample_interval_ms: 1
    )
    initial_solution =
      routing.solve_with_parameters(search_parameters(solution_limit: 20))
    initial_values = trace.to_h

    solution = routing.solve_from_assignment_with_parameters(
      initial_solution,
      search_parameters(solution_limit: 10)
    )
    values = trace.to_h

    assert_equal solution.objective_value, values[:best_solution_objective]
    assert_operator values[:solution_count], :>, 1
    refute_equal initial_values[:solution_count], values[:solution_count]
    assert_equal(
      values[:first_solution_objective] - values[:best_solution_objective],
      values[:objective_improvement]
    )
  end

  def test_does_not_record_a_warm_start_when_no_solution_is_returned
    routing = build_routing
    initial_solution =
      routing.solve_with_parameters(search_parameters(solution_limit: 10))
    trace = routing.enable_solution_trace

    solution = routing.solve_from_assignment_with_parameters(
      initial_solution,
      search_parameters(time_limit: 0)
    )

    assert_nil solution
    assert_equal EMPTY_TRACE, trace.to_h
  end

  def test_returns_an_empty_trace_when_no_solution_exists
    manager = ORTools::RoutingIndexManager.new(2, 1, 0)
    routing = ORTools::RoutingModel.new(manager)
    transit = routing.register_transit_matrix([[0, 10], [10, 0]])
    routing.set_arc_cost_evaluator_of_all_vehicles(transit)
    routing.add_dimension(transit, 0, 100, true, "Time")
    routing
      .mutable_dimension("Time")
      .cumul_var(manager.node_to_index(1))
      .set_range(0, 0)
    trace = routing.enable_solution_trace

    solution = routing.solve(first_solution_strategy: :path_cheapest_arc)

    assert_nil solution
    assert_equal EMPTY_TRACE, trace.to_h
  end

  def test_validates_and_reuses_configuration
    routing = build_routing

    error = assert_raises(ArgumentError) do
      routing.enable_solution_trace(max_samples: 0)
    end
    assert_equal "max_samples must be positive", error.message

    error = assert_raises(ArgumentError) do
      routing.enable_solution_trace(sample_interval_ms: 0)
    end
    assert_equal "sample_interval_ms must be positive", error.message

    trace = routing.enable_solution_trace
    assert_same trace, routing.enable_solution_trace

    error = assert_raises(ArgumentError) do
      routing.enable_solution_trace(max_samples: 32)
    end
    assert_equal "solution trace is already configured", error.message
  end

  def test_trace_outlives_the_routing_model
    routing = build_routing
    trace = routing.enable_solution_trace
    solution = routing.solve_with_parameters(search_parameters(solution_limit: 10))
    objective = solution.objective_value
    routing = nil
    solution = nil
    GC.start

    assert_equal objective, trace.to_h[:best_solution_objective]
  end

  def test_other_model_searches_do_not_change_a_completed_trace
    routing = build_routing
    trace = routing.enable_solution_trace
    solution = routing.solve_with_parameters(search_parameters(solution_limit: 10))
    values = trace.to_h

    assert routing.restore_assignment(solution)
    assert_equal values, trace.to_h
  end

  def test_cold_and_warm_solves_release_the_gvl
    skip if valgrind?

    routing = build_routing
    trace = routing.enable_solution_trace

    solution = assert_trace_readable_during_solve(trace) do
      routing.solve_with_parameters(search_parameters(time_limit: 1))
    end
    assert_equal solution.objective_value, trace.to_h[:best_solution_objective]

    warm_routing = build_routing
    initial_solution =
      warm_routing.solve_with_parameters(search_parameters(solution_limit: 10))
    warm_trace = warm_routing.enable_solution_trace
    assert_equal EMPTY_TRACE, warm_trace.to_h

    solution = assert_trace_readable_during_solve(warm_trace) do
      warm_routing.solve_from_assignment_with_parameters(
        initial_solution,
        search_parameters(time_limit: 1)
      )
    end
    assert_equal solution.objective_value, warm_trace.to_h[:best_solution_objective]
  end

  private

  def build_routing
    manager = ORTools::RoutingIndexManager.new(MATRIX.length, 4, 0)
    routing = ORTools::RoutingModel.new(manager)
    transit = routing.register_transit_matrix(MATRIX)
    routing.set_arc_cost_evaluator_of_all_vehicles(transit)
    routing
  end

  def search_parameters(solution_limit: nil, time_limit: nil, improvement_limit_parameters: nil)
    parameters = ORTools.default_routing_search_parameters
    parameters.first_solution_strategy = :path_cheapest_arc
    parameters.local_search_metaheuristic = :guided_local_search
    parameters.solution_limit = solution_limit if solution_limit
    parameters.time_limit = time_limit if time_limit
    parameters.improvement_limit_parameters = improvement_limit_parameters if improvement_limit_parameters
    parameters
  end

  def assert_trace_readable_during_solve(trace)
    running = true
    observed = false
    valid = true
    ready = Queue.new
    reader = Thread.new do
      ready << true
      while running
        values = trace.to_h
        if values[:solution_count] > 0
          observed = true
          valid &&=
            values[:best_solution_objective] <= values[:first_solution_objective] &&
            values[:best_solution_objective] <= values[:latest_solution_objective] &&
            values[:samples].length <= 64
        end
        Thread.pass
      end
    end
    ready.pop

    solution = yield
    running = false
    reader.join

    assert observed, "expected the reader thread to run during the solve"
    assert valid, "expected every concurrent trace snapshot to be consistent"
    solution
  ensure
    running = false
    reader&.join
  end
end
