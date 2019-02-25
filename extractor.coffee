'use strict'

isBrowser = (() =>
    try
        return true if window isnt null
    
    try
        return false if global isnt null

    throw new Error 'Unknown environment'
)()

console.log 'Running inside:', if isBrowser then 'Browser' else 'Node?'

fetch = if isBrowser then fetch else require 'node-fetch' # can be run in browsen and in the node
fs = if not isBrowser then (require 'fs').promises

registeredCode = new Map

generateFor = (locale, suplementalPlurals, tab = '\t') =>
    rules = suplementalPlurals[locale]

    if not rules
        throw new Error "Can't find rules for #{locale}"

    code = ''

    firstIf = true
    pollutions = { }

    rulesCode = ''

    for key of rules
        match = key.slice 'pluralRule-count-'.length

        if match is 'other'
            code += rulesCode
            code += "\n#{tab}return \"other\""
            break

        if firstIf
            ifCode = 'if {0}:'
        else
            ifCode = 'elif {0}:'

        rule = rules[key]

        rule = (rule.slice 0, (rule.indexOf '@')).trim()

        # console.log "#{locale}: #{match}: #{rule}"

        rule = rule.replace /([a-z]) \% (\d+)/g, (match, $1, $2) => 
            pollutionKey = "#{$1}#{$2}"

            if not pollutions[pollutionKey]
                code += "#{tab}#{pollutionKey} = #{match}\n"
                pollutions[pollutionKey] = true

            return pollutionKey
        
        rule = rule.replace /([a-z10]+) (=|!=) ([0-9\,\.]+)/g, (_, value, method, relations) =>
            replacement = ''

            relations = relations.split ","

            for relation, i in relations
                [, min, max] = /(\d+)(?:..(\d+)$|$)/.exec relation

                if i > 0 then relation += " or "

                if max
                    if method is '!=' then replacement += 'not '

                    replacement = "#{value} >= #{min} and #{value} <= #{max}"
                else
                    replacement = "#{value} #{method} #{relation}"

            return replacement
        
        rule = rule.replace (/ =/g), " =="

        rulesCode += "#{tab}#{ifCode.replace "{0}", rule}\n"
        rulesCode += "#{tab}#{tab}return \"#{match}\"\n"

    registeredCodeId = registeredCode.get code

    if registeredCodeId?
        console.log "Deduplicated #{locale} with #{registeredCodeId}"

        return "\ncardinals[\"#{locale}\"] = #{registeredCodeId}\n"

    registeredCodeId = "cardinal_#{locale}"

    registeredCode.set code, registeredCodeId

    code = "\ndef #{registeredCodeId}(n, i, v, w, f, t):\n#{code}"

    console.log code

    code += "\n\ncardinals[\"#{locale}\"] = #{registeredCodeId}\n"

    return code

CLDR_URL = 'https://raw.githubusercontent.com/unicode-cldr/cldr-core/master/supplemental/plurals.json'

downloadCLDR = () =>
    resp = await fetch(CLDR_URL)

    if resp.status isnt 200
        throw new Error "Invalid response code: #{resp.status}"

    json = await resp.json()

    return json.supplemental['plurals-type-cardinal']

save = (content) =>
    if fs
        base = await fs.readFile 'base.py', 'utf8'

        base += '\n'
        base += '\n# ========================'
        base += '\n# GENERATED AUTOMATICALLY'
        base += '\n# DON\'T MODIFY MANUALLY'
        base += '\n# ========================'
        base += '\n'

        content = base + content

        content += '\n'
        content += '\n# ================================'
        content += '\n# END AUTOMATICALLY GENERATED CODE'
        content += '\n# ================================'
        content += '\n'

        await fs.writeFile 'output.py', content

        console.info 'Wrote a file "output.py"'
    else if copy in console
        console.copy content

        console.info 'Content has been copied to your keyboard'
        console.info "Don't forget to concatenate it with base file"
    else
        console.log content

        console.info 'No other output method available, code printed above'
        console.info "Don't forget to concatenate it with base file"

(() => 
    console.log 'Downloading CLDR data...'
    locales = await downloadCLDR()

    console.log 'Generating the code...'
    code = ''

    for locale of locales
        console.log '-->', locale
        code += generateFor locale, locales

    console.log 'Output the code...'
    await save code

    console.log 'Done!'
)()