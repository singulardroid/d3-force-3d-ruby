require "d3_timer/timer"
require "d3_dispatch/dispatch"

module D3Force3d
  class Simulation

    MAX_DIMENSIONS = 3

    def initialize(nodes = [], numDimensions)
      @nDim = [MAX_DIMENSIONS, [1, numDimensions.to_i.round].max].min
      @nodes = nodes.nil? ? [] : nodes
      @initialRadius = 10
      @initialAngleRoll = Math::PI * (3 - Math.sqrt(5)) #Golden ratio angle
      @initialAngleYaw = Math::PI * 20.0 / (9 + Math.sqrt(221)) # Markov irrational number
      @alpha = 1
      @alphaMin = 0.001
      @alphaDecay = 1 - @alphaMin ** (1.0 / 300)
      @alphaTarget = 0
      @velocityDecay = 0.6
      @forces = {}
      initialize_nodes
      @event = D3Dispatch::Dispatch.dispatch("tick", "end")
      @stepper = D3Timer::Timer.new
      @stepper.restart{ |elapsed_time| step(elapsed_time) }
    end

    def self.force_simulation(nodes = [], numDimensions = 2)
      simulation = Simulation.new(nodes, numDimensions)
      simulation
    end

    def restart
      @stepper.restart{ step }
      self
    end

    def stop
      @stepper.stop
      self
    end

    def num_dimensions(*args)
      if args.length > 0
        @nDim = [MAX_DIMENSIONS, [1, args[0].to_f.round].max].min
        @forces.each{|force| initialize_force(force) }
        self
      else
        @nDim
      end
    end

    def nodes(*args)
      if args.length > 0
        @nodes = args[0].nil? ? [] : args[0]
        initialize_nodes
        @forces.each{|force| initialize_force(force) }
        self
      else
        @nodes
      end
    end

    def alpha(*args)
      if args.length > 0
        @alpha = args[0].to_f
        self
      else
        @alpha
      end
    end

    def alpha_min(*args)
      if args.length > 0
        @alphaMin = args[0].to_f
        self
      else
        @alphaMin
      end
    end

    def alpha_decay(*args)
      if args.length > 0
        @alphaDecay = args[0].to_f
        self
      else
        @alphaDecay
      end
    end

    def alpha_target(*args)
      if args.length > 0
        @alphaTarget = args[0].to_f
        self
      else
        @alphaTarget
      end
    end

    def velocity_decay(*args)
      if args.length > 0
        @velocityDecay = 1- args[0].to_f
        self
      else
        (1 - @velocityDecay).round(5)
      end
    end

    def force(name, *args)
      if args.length > 0
        if args[0].nil?
          @forces.delete(name)
        else
          @forces[name] = initialize_force(args[0])
        end
        self
      else
        @forces[name]
      end
    end

    def find(*arguments)
      args = arguments
      x = args.shift.to_f
      y = @nDim > 1 ? args.shift.to_f : 0
      z = @nDim > 2 ? args.shift.to_f : 0
      radius = args.shift || Float::INFINITY
      i = 0
      n = @nodes.length
      radius *= radius
      closest = nil

      loop do
        break if i >= n
        node = @nodes[i];
        dx = x - node["x"]
        dy = y - (node["y"] || 0)
        dz = z - (node["z"] || 0)
        d2 = dx * dx + dy * dy + dz * dz
        if (d2 < radius)
          closest = node
          radius = d2
        end
        i += 1
      end

      closest
    end

    def on(name, *args, &block)
      if args.length > 0 || block_given?
        @event.on(name, args[0], &block)
        self
      else
        @event.on(name)
      end
    end

    def tick(iterations = 1)
      n = @nodes.length
      k = 0
      loop do
        break if k >= iterations
        @alpha += (@alphaTarget - @alpha) * @alphaDecay
        @forces.each do |name, force|
          force.force(@alpha)
        end
        
        i = 0
        loop do
          break if i >= n
          node = @nodes[i]
          node = initializ_force_on_node(node)
          i += 1
        end
        k += 1
      end
      self
    end

    private

    def step(elapsed_time)
      tick
      @event.call("tick", self)
      if (@alpha < @alphaMin)
        @stepper.stop
        @event.call("end", self)
      end
    end

    def initialize_nodes
      i = 0
      n = @nodes.length
      loop do
        break if i >= n
        node = @nodes[i]
        node.transform_keys!(&:to_s)
        node["index"] = i
        node["x"] = node["fx"] if (node["fx"] != nil)
        node["y"] = node["fy"] if (node["fy"] != nil)
        node["z"] = node["fz"] if (node["fz"] != nil)
        if(is_nan?(node["x"]) || (@nDim > 1 && is_nan?(node["y"])) || (@nDim > 2 && is_nan?(node["z"])))
          radius = @initialRadius * (@nDim > 2 ? ( i == 0 ? 0 : Math.cbrt(i)): (@nDim > 1 ? Math.sqrt(i) : i))
          rollAngle = i * @initialAngleRoll
          yawAngle = i * @initialAngleYaw
          
          if (@nDim === 1)
            node["x"] = radius
          elsif (@nDim === 2)
            node["x"] = radius * Math.cos(rollAngle)
            node["y"] = radius * Math.sin(rollAngle)
          else 
            # 3 dimensions: use spherical distribution along 2 irrational number angles
            node["x"] = radius * Math.sin(rollAngle) * Math.cos(yawAngle)
            node["y"] = radius * Math.cos(rollAngle)
            node["z"] = radius * Math.sin(rollAngle) * Math.sin(yawAngle)
          end
        end
        if(is_nan?(node["vx"]) || (@nDim > 1 && is_nan?(node["vy"])) || (@nDim > 2 && is_nan?(node["vz"])))
          node["vx"] = 0
          node["vy"] = 0 if @nDim > 1
          node["vz"] = 0 if @nDim > 2
        end
        i += 1
      end
    end
    
    def initialize_force(force)
      force.intialize_force_with_nodes(@nodes, @nDim) if (force.class.method_defined?(:intialize_force_with_nodes))
      force
    end

    def x(d)
      d["x"]
    end
    
    def y(d)
      d["y"]
    end
    
    def z(d)
      d["z"]
    end
  
    def initializ_force_on_node(node)
      if (node["fx"].nil?)
        node["x"] += node["vx"] *= @velocityDecay
      else
        node["x"] = node["fx"]
        node["vx"] = 0
      end
      if (@nDim > 1)
        if (node["fy"].nil?)
          node["y"] += node["vy"] *= @velocityDecay;
        else
          node["y"] = node["fy"]
          node["vy"] = 0
        end
      end
      if (@nDim > 2)
        if (node["fz"].nil?)
          node["z"] += node["vz"] *= @velocityDecay
        else
          node["z"] = node["fz"]
          node["vz"] = 0
        end
      end
      node
    end

    def is_nan?(value)
      !value.is_a? Numeric
    end
  end
end