# Plural Ruleset Generator for Pyseeyou

This generator made to automatically download CLDR data and convert it directry into the Python code to use by [`pyseeyou` library](https://github.com/rolepoint/pyseeyou) (you most fork one yourself, probably).

## How to use?

1. Have Node.js with NPM installed

2. Obtain the repository and install the modules

    ```
    npm i
    ```

3. Check `base.py` file to be up-to-date

4. Run the generator using `npm run generator`

File should be generated to `output.py`

## QA:

### `base.py` contains different code, than in original repository!

Yes, it does. I added function to match closest locale and implemented it's usage. Thanks to [`lookup-closest-locale` package](https://github.com/format-message/format-message/tree/master/packages/lookup-closest-locale) from [vanwagonet](https://github.com/vanwagonet)'s [`format-message` library](https://www.npmjs.com/package/format-message) for Node.js.

And also I addressed “negative numbers” issue with `get_parts_of_num` function, so it should be all good now.

### Why CoffeeScript + Node.js?

I don't think I have time for now to learn Python, I just wanted to help one project.

On top of that, CoffeeScript is relatively easier to convert into Python code.

### `isBrowser`?

Yeah, this code is probably can be run within the browser and the output will be redirected to the clipboard or the console itself (if first not supported or not allowed within the context of execution).