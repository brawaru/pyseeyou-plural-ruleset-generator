'use strict'

# =====================================
#             PREPARATION
# =====================================

# Checks if browser is used
isBrowser = (() =>
    try
        return true if window isnt null

    try
        return false if global isnt null

    throw new Error 'Unknown environment'
)()

console.log 'Running inside:', if isBrowser then 'Browser' else 'Node?'

# Gets fetch function which will be used to send network requesnts
fetch = if isBrowser then fetch else require 'node-fetch'

# If running in Node.js, obtain FileSystem module to write files
fs = if not isBrowser then (require 'fs').promises

# Decimal.js library to work on decimals
decimal = if not isBrowser then (require 'decimal.js-light') else window?.Decimal


# =====================================
#            CONFIGURATION
# =====================================

# Reads parameter from the available config
readConfiguration = (browserConfigProperty, processEnvironmentVar, defaultValue) ->
    if isBrowser and browserConfigProperty?
        value = generatorOptions?[browserConfigProperty]
    else if not isBrowser and processEnvironmentVar?
        value = process.env["GENERATOR_#{processEnvironmentVar}"]

    return value or defaultValue

toBoolean = (val) ->
    if val == 'false' or val == 0
        return false
    else if val == 'true' or val == 1
        return true

    return Boolean(val)

# Gets tabs used by generator:
tab = readConfiguration 'tabs', 'TABS', '    '

# Gets URL used to download CLDR suplemental data
CLDR_URL = readConfiguration 'cldrUrl', 'CLDR_URL', 'https://raw.githubusercontent.com/unicode-cldr/cldr-core/master/supplemental/plurals.json'

# Whether should generator emit "helpful" code to make debugging little easier or not
GENERATE_DEBUG_CODE = readConfiguration 'emitDebugCode', 'EMIT_DEBUG_CODE', false

# Filename used for the CLDR rules
CLDR_RULES_FILENAME = readConfiguration 'cldrRulesFilename', 'FILENAME_CLDR_RULES', 'cldr_rules'

# Filename used for the test file
TESTS_FILENAME = readConfiguration 'testsFilename', 'FILENAME_TESTS', 'test_rules'

# Number of samples to emit in tests per type / per match
SAMPLES_COUNT = +(readConfiguration 'testSamplesLimit', 'TEST_SAMPLES_LIMIT', '3')

# Emit warnings in code about automatic generation
EMIT_WARNING_HEADERS = toBoolean (readConfiguration 'emitWarningHeaders', 'EMIT_WARNING_HEADERS', true)

# Namespace to use in imports
IMPORT_NAMESPACE = readConfiguration 'importNamespace', 'IMPORT_NAMESPACE', 'pyseeyou.'

# Resets import namespace, useful for testing without moving files around
# Does not work in browser, set `importNamespace` to `''` instead
SKIP_NAMESPACE = toBoolean (readConfiguration undefined, 'SKIP_NAMESPACE', false)

# Name of the test function at the top of test file to use by tests
TEST_FN_NAME = readConfiguration 'testFnName', 'TEST_FN_NAME', 'check'

# ======================================
#         PLURAL RULES GENERATOR
#     only cardinal rules currently.
# ======================================

# Map of already registered code
# <Code, FunctionName>
registeredCode = new Map

# Gets rules function name
getFunctionName = (locale, type) -> "#{type}_#{locale}" # cardinal_af

# Generates code for specified locale
#
# If such code was already generated before, returns
# only name of the function that had this code first
generateFor = (locale, suplementalPlurals) ->
    rules = suplementalPlurals[locale]

    if not rules
        throw new Error "Can't find rules for #{locale}"

    code = ''

    firstIf = true
    pollutions = { }

    rulesCode = ''

    testRules = Object.create null # <Match, >

    for key of rules
        match = key.slice 'pluralRule-count-'.length

        rule = rules[key]

        testsIndex = rule.indexOf '@'
        testRules[match] = rule.slice testsIndex

        rule = (rule.slice 0, testsIndex).trim()

        if match is 'other'
            if rule.length isnt 0
                throw new Error "Other match never seen having rules before"

            code += rulesCode
            code += "\n#{tab}return 'other'"
            break

        if firstIf
            ifCode = 'if {0}:'
        else
            ifCode = 'elif {0}:'

        rule = rule.replace /([a-z]) ?\% ?(\d+)/g, (match, $1, $2) =>
            pollutionKey = "#{$1}#{$2}"

            if not pollutions[pollutionKey]
                code += "#{tab}#{pollutionKey} = #{match}\n"
                pollutions[pollutionKey] = true
                console.log "  -> #{match} caused pollution"

            return pollutionKey

        # v = 0 and i = 1,2,3
        # or
        # v = 0 and i10 != 4,6,9
        # or
        # v != 0 and f10 != 4,6,9

        parts = rule.split ' or '

        for part, i in parts
            console.log "  -> part: #{part}"

            # I don't know what this regular expression doing, but it works:
            parts[i] = part.replace /([a-z10]+) ?(=|!=) ?((?:[0-9.]+,[0-9.,]+)|(?:[0-9]+)\.\.([0-9]+)|(?:\d*\.?\d*))/g, (_, value, method, relations, _relations) =>
                relations = relations.split ','
                    .map (_) => _.trim()
                relationsLen = relations.length

                console.log "    -> relation: '#{value}', '#{method}', #{relations.map((_) => "'#{_}'").join ', '}, #{relationsLen}"

                relationCode = ""
                wrapParenthesis = false

                relationsLen = relations.length
                for relation, i in relations
                    [min, max] = relation.split '..'

                    if max?
                        pollutionKey = "mf_#{value}"

                        if not pollutions[pollutionKey]
                            console.log "  -> #{value} range check caused pollution"
                            code += "#{tab}#{pollutionKey} = math.floor(#{value}) == #{value}\n"
                            pollutions[pollutionKey] = true

                        rangeCheck = "#{value} >= #{min} and #{value} <= #{max}"

                        if method is "!=" then rangeCheck = "not (#{rangeCheck})"

                        relationCode += "#{pollutionKey} and #{rangeCheck}"

                        if not ((i + 1) == relationsLen)
                            relationCode += " or "
                            wrapParenthesis = true

                        continue

                    # i10 != 1,2
                    # but not (i10 == 1 or i10 == 2)
                    if relationsLen != 1
                        relationCode += "#{value} = #{min}"

                        if not ((i + 1) == relationsLen)
                            relationCode += " or "
                            wrapParenthesis = true
                        else if method is "!="
                            relationCode = "not (#{relationCode})"
                    else
                        relationCode += "#{value} #{method} #{min}"

                console.log "    -> relation code generated: #{relationCode}"

                # TODO: remove useless wrapping
                return if wrapParenthesis then "(#{relationCode})" else relationCode

        rule = ''

        partsLen = parts.length
        for part, i in parts
            if part.includes 'or' and partsLen != 1
                rule += "(#{part})"
            else
                rule += part

            if (i + 1) != partsLen
                rule += " or "

        # rule = '('
        # rule += parts.join ') or ('
        # rule += ')'

        rule = rule.replace (/ =/g), " =="

        console.log "  -> rule code: #{rule}"

        rulesCode += "#{tab}#{ifCode.replace "{0}", rule}\n"
        rulesCode += "#{tab}#{tab}return '#{match}'\n"

    # throw new Error('oops!')

    registeredCodeId = registeredCode.get code

    if registeredCodeId?
        console.info "  -> deduplicated #{locale} with #{registeredCodeId}"

        return [ registeredCodeId, null, testRules ]

    registeredCodeId = getFunctionName locale, 'cardinal'

    registeredCode.set code, registeredCodeId

    defCode = "def #{registeredCodeId}(n, i, v, w, f, t):\n"
    if GENERATE_DEBUG_CODE then defCode += "#{tab}print(n, i, v, w, f, t)\n"
    defCode += code

    # console.log code

    return [ registeredCodeId, defCode, testRules ]

# ======================================
#           TEST GENENARATION
# ======================================

TYPE_SEGMENT_REG = /^@(integer|decimal)$/
MATCH_SEGMENT_REG = /^(.+),$/

# Gets test function name
getTestName = (locale, type) -> "test_#{type}_#{locale.replace '-', '_'}"

# Emits test function that is used to perform assertions
emitTestFunction = (code) ->
    checkCode = "def #{TEST_FN_NAME}(assertions, plural_fn):\n"
    checkCode += "#{tab}for assertion in assertions:\n"
    checkCode += "#{tab}#{tab}match, samples = assertion\n"
    checkCode += "#{tab}#{tab}for sample in samples:\n"

    fcCall = 'plural_fn(*get_parts_of_num(sample))'

    if GENERATE_DEBUG_CODE
        checkCode += "#{tab}#{tab}#{tab}result = #{fcCall}\n"
        checkCode += "#{tab}#{tab}#{tab}print(sample, 'expected to be', match, ', is', result)\n"
        checkCode += "#{tab}#{tab}#{tab}assert result == match\n"
    else
        checkCode += "#{tab}#{tab}#{tab}assert #{fcCall} == match\n"

    checkCode += '\n'

    if code.includes checkCode
        console.trace('You are trying to re-emit the check code here:')
        return code # no need to emit code again

    code += checkCode

    return code

# Generates test for specified rules
generateTestFor = (rules, locale, type) ->
    # locale => 'af'
    # type => 'cardinal'

    testBody = "def #{getTestName locale, type}():\n"

    testBody += "#{tab}assertions = [\n"

    rulesLen = (Object.keys rules).length

    i = 0

    for expectedMatch of rules
        rulesStr = rules[expectedMatch]

        console.log "  -> #{expectedMatch}: #{rulesStr}"

        # expectedMatch => other
        # rulesStr => '@integer 2~17, 100, 1000, 10000, 100000, 1000000, … @decimal 0.1~0.9, 1.1~1.7, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0, …'

        segments = rulesStr.split ' ' # split by spaces

        type = '' # Current type (last defined by type-segment)

        samples = []

        available = 0

        for segment in segments
            typeMatch = segment.match TYPE_SEGMENT_REG

            if typeMatch?
                type = typeMatch[1] # @integer, integer
                available = SAMPLES_COUNT
                continue

            if segment is '…'
                continue

            if available is 0
                continue

            available--

            match = if segment.endsWith ',' then segment.slice(0, -1) else segment

            [ start, end ] = match.split '~'

            samples.push "'#{start}'" # matches to generate

            if end?
                numBetween = getNumberBetween start, end, type is 'decimal'

                _numBetween = +numBetween

                if _numBetween < start or _numBetween > end
                    throw new Error "Cannot get number in between (start: #{start}, end: #{end}, got: #{numBetween})"

                samples.push "'#{numBetween}'"
                samples.push "'#{end}'"

        if GENERATE_DEBUG_CODE then testBody += "#{tab}#{tab}# #{rulesStr}\n"
        testBody += "#{tab}#{tab}('#{expectedMatch}', [#{samples.join()}])"
        if ++i isnt rulesLen then testBody += ','
        testBody += "\n"

    testBody += "#{tab}]\n\n"

    testBody += "#{tab}#{TEST_FN_NAME}(assertions, CARDINALS['#{locale}'])\n\n"

# Split decimal into two parts
# decimalSplit = (n) -> n.toString().split '.'

# Gets number that is half of range
#
# If `decimals` set to `false`, returns only integer
getNumberBetween = (min, max, decimals) ->
    min = decimal min
    max = decimal max

    # a = max - min  --total number
    # b = a / 2 --half of range
    # min + b --result

    half = (
        max
            .minus min
            .dividedBy 2
            # .toString()
    )

    res = min.plus half

    if decimals
        return res.toString()
    else
        return res.toFixed 0
        # return decimalSplit(res)[0]


# ======================================
#               UTILITIES
# ======================================

# Dowloads CLDR data
downloadCLDR = () ->
    resp = await fetch(CLDR_URL)

    if resp.status isnt 200
        throw new Error "Invalid response code: #{resp.status}"

    json = await resp.json()

    return json.supplemental['plurals-type-cardinal']

# Saves generated code or prints it to the console
save = (content, filename) ->
    filename += ".py"

    if fs
        await fs.writeFile "output/#{filename}", content

        console.info "Placed content in \"#{filename}\""
    else if 'copy' in console
        console.copy content

        console.info "Content of \"#{filename}\" has been copied to your keyboard"
        # console.info "Don't forget to concatenate it with base file"
    else
        console.log content

        console.info "No other output method available, code of \"#{filename}\" printed above"
        # console.info "Don't forget to concatenate it with base file"

emitHeaderWarning = (code, heading = '') ->
    heading += '# ========================'
    heading += '\n# GENERATED AUTOMATICALLY'
    heading += '\n# DON\'T MODIFY MANUALLY'
    heading += '\n# ========================'
    heading += '\n\n'

    code = heading + code

    return code

emitFooter = (code) ->
    code += '\n# ================================'
    code += '\n# END AUTOMATICALLY GENERATED CODE'
    code += '\n# ================================'
    code += '\n'

    return code

# ======================================
#              ENTRYPOINT
# ======================================

(() ->
    # => Ensure Decimal.js library available
    if not decimal
        console.log 'No Decimal.js library found in place. Please, import at once using:'
        console.log "import('https://cdn.jsdelivr.net/npm/decimal.js-light@2.5.0/decimal.js')"
        console.log 'After Importing, restart the code'

        return

    # => Download CLDR
    console.log 'Downloading CLDR data...'
    locales = await downloadCLDR()

    # => Pre-define variables and log

    console.log 'Generating the code...'

    code = 'import math\n\n'
    testsCode = ''

    # => Emit check code to tests

    testsCode = emitTestFunction(testsCode)

    # => Emit warnings?

    if EMIT_WARNING_HEADERS then code = emitHeaderWarning '', code

    # => Generate code!

    cardinalsDict = [] # Will be used to generate dictionary

    for locale of locales
        console.log '-->', locale

        console.log ' code'

        [ fnName, fnDef, testsRules ] = generateFor locale, locales

        if fnDef? then code += "#{fnDef}\n\n"

        cardinalsDict.push([ locale, fnName ])

        console.log ' test'
        testsCode += generateTestFor testsRules, locale, 'cardinal'

    # => Cardinals dict insertion

    code += 'CARDINALS = {\n'

    cardinalsCount = cardinalsDict.length

    for [locale, fnName], i in cardinalsDict
        code += "#{tab}'#{locale}': #{fnName}"
        if (i + 1) != cardinalsCount then code += ','
        code += '\n'

    code += '}\n'

    # => Generate tests import

    namespace = IMPORT_NAMESPACE

    if SKIP_NAMESPACE
        namespace = ''

    testImports = 'import pytest\n\n'

    testImports += "from #{namespace}locales import get_parts_of_num\n"
    testImports += "from #{namespace}#{CLDR_RULES_FILENAME} import CARDINALS\n\n"

    if EMIT_WARNING_HEADERS then testImports = emitHeaderWarning '', testImports

    testsCode = "#{testImports}\n#{testsCode}"

    # => Emit footers?

    if EMIT_WARNING_HEADERS
        code = emitFooter code
        testsCode = emitFooter testsCode 

    # => Output the results

    console.log 'Output the code...'

    await save code, CLDR_RULES_FILENAME
    await save testsCode, TESTS_FILENAME

    console.log 'Done!'
)()