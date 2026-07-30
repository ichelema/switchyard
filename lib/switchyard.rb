# frozen_string_literal: true

require 'logger'

require 'switchyard/version'

# frozen_string_literal: true

# Switchyard — a service skeleton with functional-programming constructs.
#
# Combines the Organizer / Action / Context pattern with Result and Option
# monads, pattern matching, and do-notation. Workflows are decomposed into
# small single-purpose actions with explicit contracts and functional error
# handling.
#
# @example Requiring the gem
#   require 'switchyard'
#   # All core modules are loaded automatically.
#
# @see Switchyard::Organizer
# @see Switchyard::Action
# @see Switchyard::Context
# @see Switchyard::Result
# @see Switchyard::Option
module Switchyard; end

require 'switchyard/deprecations'
require 'switchyard/functional/monad'
require 'switchyard/functional/enum'
require 'switchyard/functional/result'
require 'switchyard/functional/option'
require 'switchyard/functional/null'
require 'switchyard/functional/sequencer'
require 'switchyard/errors'
require 'switchyard/configuration'
require 'switchyard/i18n/localization_adapter'
require 'switchyard/localization_adapter'
require 'switchyard/localization_map'
require 'switchyard/context'
require 'switchyard/context/key_verifier'
require 'switchyard/organizer/scoped_reducable'
require 'switchyard/organizer/with_reducer'
require 'switchyard/organizer/with_reducer_log_decorator'
require 'switchyard/organizer/with_reducer_factory'
require 'switchyard/organizer/reduce_if'
require 'switchyard/organizer/reduce_if_else'
require 'switchyard/organizer/reduce_case'
require 'switchyard/organizer/reduce_until'
require 'switchyard/organizer/reduce_while'
require 'switchyard/organizer/iterate'
require 'switchyard/organizer/execute'
require 'switchyard/organizer/with_callback'
require 'switchyard/action'
require 'switchyard/organizer'
