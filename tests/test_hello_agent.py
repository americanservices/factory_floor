import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from hello_agent import hello_from_agent_88

def test_hello_from_agent_88():
    result = hello_from_agent_88()
    assert result == 'Hello from Agent 88! I am working autonomously.'
    assert 'Agent 88' in result
    print('✅ Test passed: hello_from_agent_88')

if __name__ == '__main__':
    test_hello_from_agent_88()
    print('All tests passed!')
