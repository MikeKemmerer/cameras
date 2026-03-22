# Contributing

## Reporting Issues

Open a GitHub issue with:
- A clear description of the problem
- Camera model (if relevant)
- Browser and OS details

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b my-feature`)
3. Make your changes and test in a browser
4. Commit with a clear message and open a pull request against `main`

## Development Notes

- **Languages:** HTML, JavaScript, Apache config
- Targets Panasonic AW-series PTZ cameras
- Browser-based UI — no build tools required
- Camera configs live in `multicamera/config/`; see `cameras.example.json`
- Apache config is in `sites-enabled/`; test with a local Apache instance if modifying

## Code Style

- Plain HTML/JS — no frameworks or transpilers
- Keep UI responsive and lightweight
- Use clear, descriptive variable and function names

## License

By contributing, you agree that your contributions will be licensed under the project's existing license.
