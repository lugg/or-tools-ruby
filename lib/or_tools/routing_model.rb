module ORTools
  class RoutingSolutionTrace
    private :_prepare
  end

  class RoutingModel
    private :_finish_solution_trace

    def solve(
      solution_limit: nil,
      time_limit: nil,
      lns_time_limit: nil,
      first_solution_strategy: nil,
      local_search_metaheuristic: nil,
      log_search: nil
    )
      search_parameters = ORTools.default_routing_search_parameters
      search_parameters.solution_limit = solution_limit if solution_limit
      search_parameters.time_limit = time_limit if time_limit
      search_parameters.lns_time_limit = lns_time_limit if lns_time_limit
      search_parameters.first_solution_strategy = first_solution_strategy if first_solution_strategy
      search_parameters.local_search_metaheuristic = local_search_metaheuristic if local_search_metaheuristic
      search_parameters.log_search = log_search unless log_search.nil?
      solve_with_parameters(search_parameters)
    end

    def add_disjunction(indices, penalty, max_cardinality = 1, penalty_cost_behavior = :penalize_once)
      _add_disjunction(indices, penalty, max_cardinality, penalty_cost_behavior)
    end

    def enable_solution_trace(max_samples: 64, sample_interval_ms: 50)
      options = [max_samples, sample_interval_ms]
      if @solution_trace_options
        if @solution_trace_options != options
          raise ArgumentError, "solution trace is already configured"
        end

        return @solution_trace
      end

      @solution_trace = _enable_solution_trace(max_samples, sample_interval_ms)
      @solution_trace_options = options
      @solution_trace
    end

    def solve_with_parameters(search_parameters)
      solve_with_trace do
        _solve_with_parameters(search_parameters, !@ruby_callback)
      end
    end

    def solve_from_assignment_with_parameters(assignment, search_parameters)
      solve_with_trace do
        _solve_from_assignment_with_parameters(assignment, search_parameters, !@ruby_callback)
      end
    end

    def register_unary_transit_callback(callback)
      @ruby_callback = true
      _register_unary_transit_callback(callback)
    end

    def register_transit_callback(callback)
      @ruby_callback = true
      _register_transit_callback(callback)
    end

    private

    def solve_with_trace
      return yield unless @solution_trace

      @solution_trace.__send__(:_prepare)
      solution = nil
      begin
        solution = yield
      ensure
        _finish_solution_trace(@solution_trace, solution&.objective_value)
      end
      solution
    end
  end
end
