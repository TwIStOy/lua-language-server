local vm = require 'vm.vm'

---@alias vm.object parser.object | vm.global | vm.generic

require 'vm.compiler'
require 'vm.value'
require 'vm.node'
require 'vm.def'
require 'vm.ref'
require 'vm.field'
require 'vm.doc'
require 'vm.type'
require 'vm.library'
require 'vm.runner'
require 'vm.infer'
require 'vm.global'
return vm
