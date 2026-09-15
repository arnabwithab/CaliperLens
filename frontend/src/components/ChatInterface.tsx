import { useEffect, useRef, useCallback } from 'react';
import { useChatStore } from '../store/chat';
import { sendMessage, checkHealth } from '../services/api';
import type { Message } from '../types';
import ChatMessage from './ChatMessage';
import ChatInput from './ChatInput';

function ChatInterface() {
  const {
    messages,
    isLoading,
    connectionStatus,
    sessionId,
    addMessage,
    setIsLoading,
    setConnectionStatus,
    setSessionId,
    clearMessages,
  } = useChatStore();

  const messagesEndRef = useRef<HTMLDivElement>(null);

  const checkBackendHealth = useCallback(async () => {
    try {
      const health = await checkHealth();
      setConnectionStatus(health.status === 'healthy' ? 'connected' : 'error');
    } catch {
      setConnectionStatus('error');
    }
  }, [setConnectionStatus]);

  useEffect(() => {
    checkBackendHealth();

    let storedId = localStorage.getItem('chat_session_id');
    if (!storedId) {
      storedId = crypto.randomUUID();
      localStorage.setItem('chat_session_id', storedId);
    }
    setSessionId(storedId);
  }, [checkBackendHealth, setSessionId]);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSendMessage = async (text: string) => {
    if (!text.trim()) return;

    const userMessage: Message = {
      id: Date.now(),
      type: 'user',
      content: text,
      timestamp: new Date(),
    };

    addMessage(userMessage);
    setIsLoading(true);

    try {
      const response = await sendMessage(text, sessionId);
      let chartBase64: string | undefined;
      let chartTitle: string | undefined;
      try {
        const parsed = JSON.parse(response.response);
        if (parsed.chart_data_base64) {
          chartBase64 = parsed.chart_data_base64;
          chartTitle = parsed.title;
        }
      } catch {
        /* response is not JSON, no chart */
      }
      addMessage({
        id: Date.now() + 1,
        type: 'ai',
        content: response.response,
        timestamp: new Date(),
        chartBase64,
        chartTitle,
      });
    } catch (error) {
      addMessage({
        id: Date.now() + 1,
        type: 'error',
        content: error instanceof Error ? error.message : 'An unknown error occurred',
        timestamp: new Date(),
      });
    } finally {
      setIsLoading(false);
    }
  };

  const connectionDotColor =
    connectionStatus === 'connected'
      ? 'bg-emerald-500'
      : connectionStatus === 'error'
        ? 'bg-red-500'
        : 'bg-amber-500';

  return (
    <div className="flex flex-col h-screen bg-white">
      <header className="sticky top-0 z-[100] bg-gradient-to-r from-white to-rose-50 border-b border-rose-100 shadow-sm">
        <div className="w-full px-8 py-4 flex justify-between items-center gap-12 max-lg:px-6 max-lg:gap-6 max-md:flex-wrap max-md:py-3 max-md:px-4 max-md:gap-3">
          <div className="flex items-center gap-8 flex-1 min-w-0">
            <div className="flex items-center gap-3 flex-shrink-0">
              <img
                src="/caliper_lens.png"
                alt="CaliperLens"
                className="w-8 h-8 rounded-md object-cover"
              />
              <span className="text-lg font-bold text-slate-900 -tracking-[0.5px]">
                CaliperLens
              </span>
            </div>

            <nav className="flex gap-8 max-lg:gap-6 max-md:order-3 max-md:w-full max-md:justify-center">
              <a
                href="#modules"
                className="text-[15px] text-slate-500 font-medium border border-slate-300 rounded-full px-4 py-2 hover:text-slate-900 hover:bg-slate-50 transition-all no-underline"
              >
                Modules
              </a>
              <a
                href="#clients"
                className="text-[15px] text-slate-500 font-medium border border-slate-300 rounded-full px-4 py-2 hover:text-slate-900 hover:bg-slate-50 transition-all no-underline"
              >
                Clients
              </a>
              <a
                href="#about"
                className="text-[15px] text-slate-500 font-medium border border-slate-300 rounded-full px-4 py-2 hover:text-slate-900 hover:bg-slate-50 transition-all no-underline"
              >
                About
              </a>
              <a
                href="#resources"
                className="text-[15px] text-slate-500 font-medium border border-slate-300 rounded-full px-4 py-2 hover:text-slate-900 hover:bg-slate-50 transition-all no-underline"
              >
                Resources
              </a>
              <a
                href="#SQL-Tool"
                className="text-[15px] font-bold text-blue-600 border border-slate-300 rounded-full px-4 py-2 hover:bg-slate-50 transition-all no-underline"
              >
                CaliperLens
              </a>
            </nav>
          </div>

          <div className="flex items-center gap-3 flex-shrink-0">
            <a
              href="https://github.com/arnabwithab/CaliperLens"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="CaliperLens on GitHub"
              className="flex items-center justify-center text-slate-500 hover:text-slate-900 transition-all focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
            >
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12Z" />
              </svg>
            </a>
            <button className="flex items-center gap-2 bg-gradient-to-br from-blue-600 to-blue-900 text-white font-semibold text-sm rounded-lg px-5 py-2.5 -tracking-[0.3px] transition-all hover:-translate-y-0.5 hover:shadow-lg hover:shadow-blue-600/20 active:translate-y-0">
              <span>Book a demo</span>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                <rect x="3" y="4" width="18" height="18" rx="2" />
                <path d="M16 2v4M8 2v4M3 10h18" />
              </svg>
            </button>
          </div>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto flex flex-col">
        {messages.length === 0 ? (
          <div className="flex-1 flex items-center justify-center p-10 bg-gradient-to-br from-white to-rose-50">
            <div className="flex flex-col items-center text-center max-w-[640px]">
              <div className="w-20 h-20 rounded-full bg-slate-100 flex items-center justify-center mb-6 text-blue-600">
                <img
                  src="/caliper_lens.png"
                  alt="CaliperLens"
                  width={64}
                  height={64}
                  style={{ objectFit: 'contain' }}
                />
              </div>
              <h2 className="text-[28px] font-bold text-slate-900 mb-2 -tracking-[0.5px]">
                CaliperLens
              </h2>
              <p className="text-base text-slate-500 mb-3 leading-relaxed">
                Ask questions about your healthcare data
              </p>
              <p className="text-xs text-slate-400 italic">
                Backend not publicly available due to HIPAA compliance
              </p>
            </div>
          </div>
        ) : (
          <div className="flex-1 flex flex-col p-6 md:p-8 gap-4 overflow-y-auto bg-gradient-to-br from-white to-rose-50">
            {messages.map((message) => (
              <ChatMessage key={message.id} message={message} />
            ))}
            {isLoading && (
              <div className="flex items-center">
                <div className="flex gap-1.5 bg-slate-100 rounded-lg p-3">
                  <span className="w-2 h-2 rounded-full bg-blue-600 animate-bounce-dot [animation-delay:-0.32s]" />
                  <span className="w-2 h-2 rounded-full bg-blue-600 animate-bounce-dot [animation-delay:-0.16s]" />
                  <span className="w-2 h-2 rounded-full bg-blue-600 animate-bounce-dot" />
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      <footer className="bg-gradient-to-r from-white to-rose-50 border-t border-rose-100 px-8 py-4 md:px-8 max-md:px-4">
        <div className="flex justify-between items-center mb-4 min-h-[32px] max-md:flex-col max-md:gap-2 max-md:items-start">
          <div className="flex items-center gap-2 px-3 py-1.5 bg-gradient-to-r from-slate-100 to-rose-50 rounded-full text-[13px] font-medium text-slate-500">
            <span className={`w-2 h-2 rounded-full ${connectionDotColor} animate-pulse-dot`} />
            <span>
              {connectionStatus === 'connected' && 'Connected'}
              {connectionStatus === 'error' && 'Disconnected'}
              {connectionStatus === 'checking' && 'Checking...'}
            </span>
          </div>
          {messages.length > 0 && (
            <button
              onClick={clearMessages}
              className="bg-transparent border-none text-[13px] text-slate-500 font-medium px-3 py-1.5 rounded-md transition-all hover:bg-gradient-to-r hover:from-slate-100 hover:to-rose-50 hover:text-slate-900"
            >
              Clear conversation
            </button>
          )}
        </div>
        <ChatInput onSendMessage={handleSendMessage} disabled={isLoading} />
      </footer>
    </div>
  );
}

export default ChatInterface;
