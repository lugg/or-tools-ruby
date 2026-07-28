require_relative "test_helper"

class RoutingPiecewiseCumulCostTest < Minitest::Test
  def test_adds_piecewise_cost_to_objective
    assert_equal 0, solve(elapsed: 4).objective_value
    assert_equal 10, solve(elapsed: 10).objective_value
    assert_equal 18, solve(elapsed: 12).objective_value
  end

  def test_retains_cost_for_warm_solve
    routing, dimension = build_routing(elapsed: 12)
    set_cost(dimension, routing.end(0))
    initial_solution = routing.read_assignment_from_routes([[1]], true)

    solution = routing.solve_from_assignment_with_parameters(
      initial_solution,
      ORTools.default_routing_search_parameters
    )

    assert_equal 18, solution.objective_value
  end

  def test_copies_cost_into_model
    routing, dimension = build_routing(elapsed: 12)
    breakpoints = [5, 10]
    slopes = [0, 2, 4]

    dimension.set_cumul_var_piecewise_linear_cost(
      routing.end(0),
      0,
      breakpoints,
      slopes
    )
    breakpoints.clear
    slopes.clear
    GC.start

    assert_equal 18, routing.solve(first_solution_strategy: :path_cheapest_arc).objective_value
  end

  def test_does_not_change_objective_when_disabled
    routing, _dimension = build_routing(elapsed: 12)

    assert_equal 0, routing.solve(first_solution_strategy: :path_cheapest_arc).objective_value
  end

  def test_validates_curve
    routing, dimension = build_routing(elapsed: 12)
    index = routing.end(0)

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, -1, [5], [0, 1])
    end
    assert_equal "initial_level must be nonnegative", error.message

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, 0, [], [0])
    end
    assert_equal "breakpoints must not be empty", error.message

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, 0, [5], [0])
    end
    assert_equal "slopes must contain one more value than breakpoints", error.message

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, 0, [5, 5], [0, 1, 2])
    end
    assert_equal "breakpoints must be strictly increasing", error.message

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, 0, [5], [0, -1])
    end
    assert_equal "slopes must be nonnegative", error.message

    error = assert_raises(ArgumentError) do
      dimension.set_cumul_var_piecewise_linear_cost(index, 0, [5], [1, 2])
    end
    assert_equal "cost must be nonnegative at zero", error.message
  end

  private

  def solve(elapsed:)
    routing, dimension = build_routing(elapsed: elapsed)
    set_cost(dimension, routing.end(0))
    routing.solve(first_solution_strategy: :path_cheapest_arc)
  end

  def build_routing(elapsed:)
    manager = ORTools::RoutingIndexManager.new(2, 1, 0)
    routing = ORTools::RoutingModel.new(manager)
    zero_transit = routing.register_transit_matrix([[0, 0], [0, 0]])
    time_transit = routing.register_transit_matrix([[0, 0], [elapsed, 0]])

    routing.set_arc_cost_evaluator_of_all_vehicles(zero_transit)
    routing.add_dimension(time_transit, 0, 100, true, "Time")

    [routing, routing.mutable_dimension("Time")]
  end

  def set_cost(dimension, index)
    dimension.set_cumul_var_piecewise_linear_cost(
      index,
      0,
      [5, 10],
      [0, 2, 4]
    )
  end
end
