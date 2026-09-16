import { Analytics } from '@vercel/analytics/react';
import ChatInterface from './components/ChatInterface';

function App() {
  return (
    <div className="w-full h-screen flex flex-col bg-white">
      <ChatInterface />
      <Analytics />
    </div>
  );
}

export default App;
