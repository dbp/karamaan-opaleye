{-# LANGUAGE MultiParamTypeClasses #-}

module Karamaan.Opaleye.Manipulation where

import Karamaan.Opaleye.Wire (Wire(Wire))
import Karamaan.Opaleye.ExprArr (Scope, ExprArr, runExprArr'', eq, scopeOfWire,
                                plus)
import Karamaan.Opaleye.QueryColspec
import Database.HaskellDB.PrimQuery (PrimExpr)
import Data.Profunctor (Profunctor, dimap)
import Data.Profunctor.Product (ProductProfunctor, empty, (***!),
                                ProductContravariant, point, (***<),
                                defaultEmpty, defaultProfunctorProduct,
                                defaultPoint, defaultContravariantProduct)
import Data.Functor.Contravariant (Contravariant, contramap)
import Control.Applicative (Applicative, (<*>), pure)
import Data.Monoid (Monoid, mempty, mappend, (<>))
import Database.HaskellDB.Sql (SqlDelete)
import Database.HaskellDB.Sql.Generate (sqlDelete)
import Database.HaskellDB.Sql.Default (defaultSqlGenerator)
import Database.HaskellDB.Sql.Print (ppDelete)
import Control.Arrow ((&&&), (<<<), arr, first)
import Karamaan.Opaleye.Default (Default, def)

data Table a = Table String a

-- TODO: The MWriter will insert every table column into the scope
-- even if the projector components projects some columns away.  Is
-- this what we want?  It will probably be hard to do something
-- different without introducting another ProductProfunctor.
data TableExprRunner t e = TableExprRunner (MWriter Scope t) (t -> e)

newtype TableMaybeWrapper a b = TableMaybeWrapper (a -> b)

newtype MWriter2 m a = MWriter2 (a -> a -> m)

newtype Assocer a = Assocer (MWriter2 [(String, PrimExpr)] a)

instance Functor (TableExprRunner a) where
  fmap f (TableExprRunner w ff) = TableExprRunner w (fmap f ff)

instance Applicative (TableExprRunner a) where
  -- TODO: Surely need a default way of doing 'contramap (const ()) point'
  pure x = TableExprRunner (contramap (const ()) point) (pure x)
  TableExprRunner w ff <*> TableExprRunner w' ff' =
    TableExprRunner (w <> w') (ff <*> ff')

instance Profunctor TableExprRunner where
  dimap f g (TableExprRunner w ff) = TableExprRunner (contramap f w) (d ff)
    where d = dimap f g

instance ProductProfunctor TableExprRunner where
  empty = defaultEmpty
  (***!) = defaultProfunctorProduct

instance Functor (TableMaybeWrapper a) where
  fmap f (TableMaybeWrapper ff) = TableMaybeWrapper (fmap f ff)

instance Applicative (TableMaybeWrapper a) where
  pure = TableMaybeWrapper . pure
  TableMaybeWrapper ff <*> TableMaybeWrapper fx = TableMaybeWrapper (ff <*> fx)

instance Profunctor TableMaybeWrapper where
  dimap f g (TableMaybeWrapper ff) = TableMaybeWrapper (dimap f g ff)

instance ProductProfunctor TableMaybeWrapper where
  empty = defaultEmpty
  (***!) = defaultProfunctorProduct

instance Monoid m => Monoid (MWriter2 m a) where
  mempty = MWriter2 (pure mempty)
  MWriter2 w `mappend` MWriter2 w' = MWriter2 (w <> w')

instance Contravariant (MWriter2 m) where
  contramap f (MWriter2 w) = MWriter2 (\a b -> w (f a) (f b))

instance Monoid m => ProductContravariant (MWriter2 m) where
  point = defaultPoint
  (***<) = defaultContravariantProduct

instance Monoid (Assocer a) where
  mempty = Assocer mempty
  Assocer w `mappend` Assocer w' = Assocer (w <> w')

instance Contravariant Assocer where
  contramap f (Assocer w) = Assocer (contramap f w)

instance ProductContravariant Assocer where
  point = defaultPoint
  (***<) = defaultContravariantProduct

arrangeDelete :: TableExprRunner t a -> Table t -> ExprArr a (Wire Bool)
                 -> SqlDelete
arrangeDelete (TableExprRunner (Writer makeScope) adaptCols)
              (Table tableName tableCols)
              conditionExpr
  = sqlDelete defaultSqlGenerator tableName [condition]
  where condition = runExprArr'' conditionExpr ((adaptCols &&& makeScope) tableCols)

instance Default TableExprRunner (Wire a) (Wire a) where
  def = TableExprRunner (Writer scopeOfWire) id

test :: String
test = show (ppDelete sqlDelete')
  where table = Table "tablename" ((Wire "col1", Wire "col2"), Wire "col3") :: Table ((Wire Int, Wire Int), Wire Int)
        condExpr = eq <<< first plus :: ExprArr ((Wire Int, Wire Int), Wire Int) (Wire Bool)
        sqlDelete' = arrangeDelete def table condExpr