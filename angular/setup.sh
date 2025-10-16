#!/bin/bash

echo "🚀 Last9 Angular Monitoring Sample Setup"
echo "========================================"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

echo "✅ Node.js and npm are installed"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
npm install

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo "✅ Dependencies installed successfully"
echo ""

# Setup environment files
echo "⚙️  Setting up environment files..."

# Check if environment files already exist
if [ -f "src/environments/environment.ts" ]; then
    echo "⚠️  environment.ts already exists, skipping..."
else
    cp src/environments/environment.example.ts src/environments/environment.ts
    echo "✅ Created src/environments/environment.ts"
fi

if [ -f "src/environments/environment.prod.ts" ]; then
    echo "⚠️  environment.prod.ts already exists, skipping..."
else
    cp src/environments/environment.prod.example.ts src/environments/environment.prod.ts
    echo "✅ Created src/environments/environment.prod.ts"
fi

echo ""
echo "🎯 Next Steps:"
echo "1. Edit src/environments/environment.ts and add your Last9 token"
echo "2. Replace 'YOUR_LAST9_TOKEN_HERE' with your actual Last9 authentication token"
echo "3. Run 'npm start' to start the development server"
echo "4. Open http://localhost:4200 in your browser"
echo ""
echo "📚 Documentation:"
echo "- README.md - Project overview and setup instructions"
echo "- ANGULAR_LAST9_MONITORING_GUIDE.md - Comprehensive monitoring guide"
echo "- LAST9_OTEL_INTEGRATION_GUIDE.md - OpenTelemetry integration details"
echo ""
echo "🔗 Last9 Dashboard: https://app.last9.io"
echo ""
echo "✨ Setup complete! Happy monitoring!"
