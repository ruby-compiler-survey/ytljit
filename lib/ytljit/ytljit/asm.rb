module YTLJit

  class StepHandler
    def step_handler(*regs)
      STDERR.print "execute: 0x#{regs[0].to_s(16)}\n"
      STDERR.print CodeSpace.disasm_cache[regs[0].to_s(16)], "\n"
      STDERR.print regs.inspect
      STDERR.print "\n"
     end
  end

  class Generator
    def initialize(asm)
      @asm = asm
    end
    attr :asm
  end

  class OutputStream
    def asm=(a)
      @asm = a
    end

    def base_address
      0
    end

    def var_base_address
      OpVarImmidiateAddress.new(lambda {0})
    end
  end

  class FileOutputStream<OutputStream
    def initialize(st)
      @stream = st
    end

    def emit(code)
      @stream.write(code)
    end
  end

  class Assembler
    @@value_table_cache = {}
    @@value_table_entity = ValueSpace.new

    def self.set_value_table(out)
      @@value_table_cache = {}
      @@value_table_entity = out
    end

    def self.get_value_table(out)
      [@@value_table_entity, @@value_table_cache]
    end

    def initialize(out, gen = GeneratorExtend)
      @generator = gen.new(self)
      @output_stream = out
      @retry_mode = false
      @step_mode = false
      reset
    end

    def reset
      @current_address = @output_stream.base_address
      @offset = 0
    end

    attr_accessor :current_address
    attr_accessor :step_mode

    def var_current_address
      func = lambda {
        @current_address
      }
      OpVarImmidiateAddress.new(func)
    end

    attr_accessor :generated_code

    def store_outcode(out)
      update_state(out)
      @offset += out.bytesize
      @output_stream.emit(out)
      out
    end

    def update_state(out)
      @current_address += out.bytesize
      out
    end

    def with_retry(&body)
      org_base_address = @output_stream.base_address
      yield
      @retry_mode = true
      while org_base_address != @output_stream.base_address do
        org_base_address = @output_stream.base_address
        reset
        @output_stream.reset
        yield
        @output_stream.update_refer
      end
      @retry_mode = false
    end

    def add_value_entry(val)
      off= nil
      unless off = @@value_table_cache[val] then
        off = @@value_table_entity.current_pos
        @@value_table_entity.emit([val].pack("Q"))
        @@value_table_cache[val] = off
      end

      @@value_table_entity.var_base_address(off)
    end

    def add_var_immdiate_retry_func(mn, args)
      if args.any? {|e| e.is_a?(OpVarImmidiateAddress) } and 
         !@retry_mode then
        offset = @offset
        stfunc = lambda {
          with_current_address(@output_stream.base_address + offset) {
            @output_stream[offset] = @generator.send(mn, *args)
          }
        }
        args.each do |e|
          if e.is_a?(OpVarImmidiateAddress) then
            e.add_refer(stfunc)
          end
        end
      end
    end

    def method_missing(mn, *args)
      out = @generator.call_stephandler
      store_outcode(out)

      add_var_immdiate_retry_func(mn, args)
      out = @generator.send(mn, *args)
      if out.is_a?(Array) then
        store_outcode(out[0])
      else
        store_outcode(out)
      end
      out
    end

    private

    def with_current_address(address)
      org_curret_address = self.current_address
      self.current_address = address
      yield
      self.current_address = org_curret_address
    end
  end
end
