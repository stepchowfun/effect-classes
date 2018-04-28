{

module Parser (parse) where

import Lexer (Token(..))
import Syntax (EVar(..), TVar(..), ITerm(..), Type(..))

}

%name parse
%tokentype { Token }
%monad { Either String }
%error { parseError }

%token
  ':'      { TokenAnno }
  '->'     { TokenArrow }
  '.'      { TokenDot }
  forall   { TokenForAll }
  x        { TokenId $$ }
  '('      { TokenLParen }
  lambda   { TokenLambda }
  ')'      { TokenRParen }

%nonassoc ':'
%left '.'
%right '->'
%nonassoc forall x '(' lambda ')'
%nonassoc APP

%%

ITerm : x                             { IEVar (UserEVar $1) }
     | lambda EVarList '->' ITerm     { foldr (\(x, t) e -> IEAbs (UserEVar x) t e) $4 (reverse $2) }
     | ITerm ITerm %prec APP          { IEApp $1 $2 }
     | ITerm ':' Type                 { IEAnno $1 $3 }
     | '(' ITerm ')'                  { $2 }

Type : x                              { TVar (UserTVar $1) }
     | Type '->' Type                 { TArrow $1 $3 }
     | forall TVarList '.' Type       { foldr (\x t -> TForAll (UserTVar x) t) $4 (reverse $2) }
     | '(' Type ')'                   { $2 }

EVarList : x                          { [($1, Nothing)] }
        | '(' x ':' Type ')'          { [($2, Just $4)] }
        | EVarList x                  { ($2, Nothing) : $1 }
        | EVarList '(' x ':' Type ')' { ($3, Just $5) : $1 }

TVarList : x                          { [$1] }
        | TVarList x                  { $2 : $1 }

{

parseError :: [Token] -> Either String a
parseError x = Left ("Parse error: " ++ show x)

}
