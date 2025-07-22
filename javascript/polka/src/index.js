require('./instrumentation');
const polka = require('polka');
const { PolkaInstrumentation } = require('./polka-instrumentation');
const usersRoutes = require('./routes/users.routes');

const app = polka();
app.use('/users', usersRoutes);
app.get('/', (req, res) => {
  res.end('Hello from Polka!');
});

// Integrate Polka auto-instrumentation (InstrumentationBase style)
const polkaInstrumentation = new PolkaInstrumentation();
polkaInstrumentation.patchApp(app, { serviceName: 'polka-app' });

app.listen(3000, err => {
  if (err) throw err;
  console.log('> Running on localhost:3000');
}); 