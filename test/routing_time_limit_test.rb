require_relative "test_helper"

class RoutingTimeLimitTest < Minitest::Test
  def test_restoration_limit_can_be_reset_after_timeout
    routing = build_routing
    routing.close_model
    routing.update_time_limit(0)

    assert_nil routing.read_assignment_from_routes([[1, 2]], true)
    assert_equal :fail, routing.status

    routing.update_time_limit(0.5)
    assignment = routing.read_assignment_from_routes([[1, 2]], true)

    refute_nil assignment
    assert_equal 4, assignment.objective_value
    assert_equal :success, routing.status
  end

  def test_solve_replaces_restoration_time_limit
    routing = build_routing
    routing.close_model
    routing.update_time_limit(0.5)
    assignment = routing.read_assignment_from_routes([[1, 2]], true)
    refute_nil assignment

    routing.update_time_limit(0)
    parameters = ORTools.default_routing_search_parameters
    parameters.time_limit = 1
    parameters.solution_limit = 1
    solution = routing.solve_from_assignment_with_parameters(assignment, parameters)

    refute_nil solution
    assert_equal 4, solution.objective_value
  end

  def test_rejects_invalid_time_limits
    routing = build_routing

    [-1, Float::INFINITY, -Float::INFINITY, Float::NAN].each do |seconds|
      error = assert_raises(ArgumentError) { routing.update_time_limit(seconds) }
      assert_equal "time limit must be finite and nonnegative", error.message
    end
  end

  private

  def build_routing
    manager = ORTools::RoutingIndexManager.new(3, 1, 0)
    routing = ORTools::RoutingModel.new(manager)
    transit = routing.register_transit_matrix([[0, 1, 2], [1, 0, 1], [2, 1, 0]])
    routing.set_arc_cost_evaluator_of_all_vehicles(transit)
    routing
  end
end
