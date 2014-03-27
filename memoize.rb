module Memoize
  def remember(*names)
    names.each do |name|
      memory = {}

      original_method = instance_method(name)

      define_method(name) do |*args|
        memory[self.object_id] ||= {}

        if memory[self.object_id].has_key?(args)
          memory[self.object_id][args]
        else
          original = original_method.bind(self)

          memory[self.object_id][args] = original.call(*args)
        end
      end
    end
  end
end
