# gamza-dynamic_v2
- 라이브러리 구조를 개편하였습니다.
- hook data가 사라진 최신 버전을 적용하였습니다.
## Minimum Test
- `inputBytecode`: 컴파일된 json 파일을 받아 테스팅을 진행합니다
    - `_std`: `poolmanager.t.sol`에 존재하는 훅 테스트케이스를 수행합니다
    - `_all`: `poolmanager.t.sol`에 존재하는 모든 테스트케이스를 수행합니다
- `inputPoolkey`: 온체인상의 poolkey를 받아 테스팅을 진행합니다
    - `_std`: `poolmanager.t.sol`에 존재하는 훅 테스트케이스를 수행합니다
    - `_noMock`: `MockContract`(proxy)를 사용하지 않는 테스트케이스를 수행합니다